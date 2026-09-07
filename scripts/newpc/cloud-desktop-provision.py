#!/usr/bin/env python3
"""Provision the Hetzner Cloud host that the cloud workstation runs on.

This script builds the *infrastructure* for `grotap-cloud-01`: a firewall, a data
volume, and the server itself. It does not install Windows — that is a manual,
console-driven step documented in `CLOUD-DESKTOP.md`, and this script prints the
exact commands to start it once the hardware exists.

Usage (secrets injected by Doppler, never inline):

    # show what would be built, and what it costs -- creates nothing
    doppler run -p grotap -c prd -- python scripts/newpc/cloud-desktop-provision.py

    # actually build it
    doppler run -p grotap -c prd -- python scripts/newpc/cloud-desktop-provision.py --apply

    # tear it back down (asks you to type the server name)
    doppler run -p grotap -c prd -- python scripts/newpc/cloud-desktop-provision.py --destroy

`--dry-run` is the DEFAULT and `--apply` is required to create anything. This is a
recurring-spend action — roughly $123/month once the server is up — so running the
script to find out what it does must not leave a bill behind.

Idempotent. Every resource is looked up by name first; a second `--apply` reports
"exists" and changes nothing. Re-running after a partial failure resumes.

Required env var (injected by Doppler):
    HETZNER_API_TOKEN   — a Hetzner *Cloud* project token with read+write

The token is never accepted as an argument and never printed.
"""

import argparse
import os
import sys
import time
from typing import Any, Dict, List, Optional

import httpx

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

# --------------------------------------------------------------------------- #
# API base URLs
#
# Hetzner runs TWO separate APIs with different hosts, different tokens and
# different resource models, and the names are close enough to lose an hour to:
#
#   Cloud    https://api.hetzner.cloud/v1   servers, volumes, firewalls, images
#                                           -> project token, HETZNER_API_TOKEN
#   Console  https://api.hetzner.com/v1     STORAGE BOXES (the backup target from
#                                           Phase 1), dedicated servers, DNS
#                                           -> a different token entirely
#
# The Storage Box that `scripts\backup-workstation\` writes to lives on the
# SECOND one. Nothing in this file touches it; if you came here looking for the
# Storage Box, you are on the wrong API.
# --------------------------------------------------------------------------- #
API = "https://api.hetzner.cloud/v1"

# ------------------------------------------------------------------ the plan --
SERVER_NAME_DEFAULT = "grotap-cloud-01"
SERVER_TYPE = "ccx23"          # 4 dedicated vCPU / 16 GB / 160 GB NVMe
LOCATION = "hil"               # Hillsboro, Oregon -- ~20 miles from Portland
FIREWALL_NAME = "grotap-cloud-desktop"
VOLUME_SIZE_GB = 250

# `ubuntu-24.04` is a PLACEHOLDER and nothing more. Hetzner Cloud's ISO library is
# public-only (Windows Server 2019/2022/2025 and virtio-win; no Windows 11) and it
# accepts no private ISO uploads, so Windows 11 is installed from the rescue system
# with QEMU writing straight to /dev/sda. That overwrites whatever image was laid
# down here. The image only has to be something that boots, so the server reaches
# "running" and rescue mode can be enabled.
PLACEHOLDER_IMAGE = "ubuntu-24.04"

LABELS = {"role": "cloud-workstation", "managed-by": "cloud-desktop-provision"}

# Prices read from the live Hetzner Cloud pricing API on 2026-09-06 (USD, VAT 0%).
# Used only as a fallback when the pricing endpoint cannot be read or its shape
# changes; a normal run quotes live numbers and says which it used.
FALLBACK_PRICES = {
    "server_monthly": 102.99,      # ccx23 in hil
    "ipv4_monthly": 0.60,
    "volume_per_gb_month": 0.0767,
    "image_per_gb_month": 0.0199,  # snapshots -- not created here, shown for context
}

# Non-Hetzner recurring costs, shown in the dry-run total so the number on screen is
# the number on the card. See CLOUD-DESKTOP.md for the full itemisation.
CONTEXT_COSTS = [
    ("Hetzner Storage Box BX21, 5 TB (already live, Phase 1)", 12.00),
    ("M365 Business Premium, 1 seat (the Windows licence)", 22.00),
]

TIMEOUT = httpx.Timeout(30.0)
ACTION_POLL_SECONDS = 3
ACTION_TIMEOUT_SECONDS = 600


class HetznerError(RuntimeError):
    """An error the Hetzner API reported, carrying its own message text."""


# --------------------------------------------------------------------- http --
def _client(token: str) -> httpx.Client:
    return httpx.Client(
        base_url=API,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        timeout=TIMEOUT,
    )


def _api_error_text(resp: httpx.Response) -> str:
    """Pull Hetzner's own error message out of a response, whatever shape it is."""
    try:
        err = resp.json().get("error") or {}
        code = err.get("code", "")
        message = err.get("message", "")
        details = err.get("details")
        text = f"{code}: {message}" if code else message
        if details:
            text = f"{text} ({details})"
        return text or resp.text[:400]
    except Exception:
        return resp.text[:400]


def call(
    client: httpx.Client,
    method: str,
    path: str,
    payload: Optional[Dict[str, Any]] = None,
    params: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """One API call, with a short retry on the transient states Hetzner uses.

    409 `conflict`/`locked` and 423 mean another action is still holding the
    resource -- normal when creating a server and attaching a volume back to back.
    429 is rate limiting. Everything else fails immediately and loudly, with the
    API's own error text rather than a bare status code.
    """
    for attempt in range(6):
        resp = client.request(method, path, json=payload, params=params)
        if resp.status_code in (409, 423, 429):
            wait = 2 ** attempt
            print(f"  ... {resp.status_code} from {method} {path}, retrying in {wait}s")
            time.sleep(wait)
            continue
        if resp.status_code >= 400:
            raise HetznerError(f"{method} {path} -> {resp.status_code} {_api_error_text(resp)}")
        if not resp.content:
            return {}
        return resp.json()
    raise HetznerError(f"{method} {path} still busy after 6 attempts -- resource is locked")


def wait_for_action(
    client: httpx.Client,
    action: Optional[Dict[str, Any]],
    resource_path: Optional[str] = None,
) -> None:
    """Block until a Hetzner action finishes, and fail loudly if it errored.

    Every create/attach/delete in the Cloud API returns immediately with an action
    in status `running`. Treating that as success is the classic mistake here: the
    next call then fails with `locked` or, worse, silently races. `resource_path`
    (e.g. `/servers/123`) is polled first because the global `/actions/{id}` route
    is the older one; we fall back to it if the scoped route is not present.
    """
    if not action:
        return
    action_id = action.get("id")
    if action_id is None:
        return
    if action.get("status") == "success":
        return
    command = action.get("command", "action")

    deadline = time.time() + ACTION_TIMEOUT_SECONDS
    paths: List[str] = []
    if resource_path:
        paths.append(f"{resource_path}/actions/{action_id}")
    paths.append(f"/actions/{action_id}")

    while True:
        current = None
        for p in paths:
            try:
                current = call(client, "GET", p).get("action")
                break
            except HetznerError as exc:
                if "404" in str(exc):
                    continue
                raise
        if current is None:
            raise HetznerError(f"cannot poll action {action_id} ({command}) on any known path")

        status = current.get("status")
        if status == "success":
            return
        if status == "error":
            err = current.get("error") or {}
            raise HetznerError(
                f"action {action_id} ({command}) FAILED: "
                f"{err.get('code', 'unknown')}: {err.get('message', 'no message')}"
            )
        if time.time() > deadline:
            raise HetznerError(
                f"action {action_id} ({command}) still '{status}' after "
                f"{ACTION_TIMEOUT_SECONDS}s -- check the Hetzner console"
            )
        time.sleep(ACTION_POLL_SECONDS)


def wait_for_actions(
    client: httpx.Client,
    response: Dict[str, Any],
    resource_path: Optional[str] = None,
) -> None:
    """Wait on the primary action AND every `next_actions` entry.

    A server create returns `action` (the create) plus `next_actions` (start,
    attach volume, apply firewall). Waiting only on the first one is how a script
    comes to report success on a server whose volume never attached.
    """
    wait_for_action(client, response.get("action"), resource_path)
    for nxt in response.get("next_actions") or []:
        wait_for_action(client, nxt, resource_path)


# ------------------------------------------------------------------ lookups --
def find_by_name(client: httpx.Client, kind: str, name: str) -> Optional[Dict[str, Any]]:
    """Return the resource of `kind` (servers/volumes/firewalls) with this exact name.

    This is the whole idempotency story: nothing is created without asking first,
    so a re-run after a network drop or a Ctrl-C picks up where it stopped instead
    of building a second copy of a $103/month server.
    """
    items = call(client, "GET", f"/{kind}", params={"name": name}).get(kind, [])
    for item in items:
        if item.get("name") == name:
            return item
    return None


def resolve_ssh_key(client: httpx.Client, wanted: Optional[str]) -> Dict[str, Any]:
    """Pick the SSH key to inject, and refuse to guess when it matters.

    Without a key on the server there is no way into the rescue system, and rescue
    is the only path by which Windows 11 gets installed -- so this is a hard
    failure, not a warning.
    """
    keys = call(client, "GET", "/ssh_keys").get("ssh_keys", [])
    if not keys:
        raise HetznerError(
            "no SSH keys in this Hetzner Cloud project. Add your public key in the "
            "console (Security > SSH Keys) before provisioning -- rescue mode is "
            "key-only and there is no other way to reach the box."
        )
    if wanted:
        for k in keys:
            if k.get("name") == wanted:
                return k
        names = ", ".join(k.get("name", "?") for k in keys)
        raise HetznerError(f"no SSH key named '{wanted}'. Keys in this project: {names}")
    if len(keys) == 1:
        return keys[0]
    names = ", ".join(k.get("name", "?") for k in keys)
    raise HetznerError(
        f"{len(keys)} SSH keys in this project -- pass --ssh-key NAME to choose one. "
        f"Available: {names}"
    )


# ------------------------------------------------------------------ pricing --
def _price(node: Any) -> Optional[float]:
    """Read a Hetzner price node ({'net': '1.23', 'gross': '1.23'}) as a float.

    Gross is preferred; the account is VAT 0% so the two are equal today, but if
    that ever changes the number people care about is the one they are charged.
    """
    if not isinstance(node, dict):
        return None
    for field in ("gross", "net"):
        raw = node.get(field)
        if raw is not None:
            try:
                return float(raw)
            except (TypeError, ValueError):
                continue
    return None


def fetch_prices(client: httpx.Client) -> Dict[str, Any]:
    """Quote from the live pricing API, falling back to the values captured 2026-09-06.

    Prices are the reason this script defaults to a dry run, so they should be real
    rather than remembered. Any shape change in the endpoint degrades to the
    fallback table and says so on screen, instead of crashing or quietly lying.
    """
    prices: Dict[str, Any] = dict(FALLBACK_PRICES)
    prices["source"] = "cached 2026-09-06 (live pricing API unavailable)"
    prices["currency"] = "USD"
    try:
        pricing = call(client, "GET", "/pricing").get("pricing", {})
    except HetznerError as exc:
        print(f"  [warn] could not read live pricing ({exc}); using cached figures")
        return prices

    prices["currency"] = pricing.get("currency", "USD")
    got_server_price = False

    for st in pricing.get("server_types", []) or []:
        if st.get("name") != SERVER_TYPE:
            continue
        for entry in st.get("prices", []) or []:
            if entry.get("location") == LOCATION:
                value = _price(entry.get("price_monthly"))
                if value is not None:
                    prices["server_monthly"] = value
                    got_server_price = True

    for ip in pricing.get("primary_ips", []) or []:
        if ip.get("type") != "ipv4":
            continue
        for entry in ip.get("prices", []) or []:
            if entry.get("location") == LOCATION:
                value = _price(entry.get("price_monthly"))
                if value is not None:
                    prices["ipv4_monthly"] = value

    volume_price = _price((pricing.get("volume") or {}).get("price_per_gb_month"))
    if volume_price is not None:
        prices["volume_per_gb_month"] = volume_price
    image_price = _price((pricing.get("image") or {}).get("price_per_gb_month"))
    if image_price is not None:
        prices["image_per_gb_month"] = image_price

    if got_server_price:
        prices["source"] = "live Hetzner pricing API"
    return prices


def print_cost_table(prices: Dict[str, Any], volume_gb: int) -> None:
    cur = prices.get("currency", "USD")
    server = prices["server_monthly"]
    ipv4 = prices["ipv4_monthly"]
    per_gb = prices["volume_per_gb_month"]
    volume = per_gb * volume_gb
    hetzner_total = server + ipv4 + volume

    print()
    print(f"  Projected monthly cost ({cur}, prices: {prices['source']})")
    print("  " + "-" * 68)
    print(f"  {'server ' + SERVER_TYPE + ' @ ' + LOCATION:<56}{server:>10.2f}")
    print(f"  {'primary IPv4':<56}{ipv4:>10.2f}")
    print(f"  {'volume ' + str(volume_gb) + ' GB @ ' + format(per_gb, '.4f') + '/GB':<56}{volume:>10.2f}")
    print(f"  {'firewall':<56}{0.0:>10.2f}")
    print("  " + "-" * 68)
    print(f"  {'created by this script':<56}{hetzner_total:>10.2f}")
    print()
    running = hetzner_total
    for label, amount in CONTEXT_COSTS:
        print(f"  {label:<56}{amount:>10.2f}")
        running += amount
    snapshot = prices["image_per_gb_month"] * 60
    print(f"  {'golden-image snapshot, ~60 GB (taken by hand later)':<56}{snapshot:>10.2f}")
    running += snapshot
    print("  " + "-" * 68)
    print(f"  {'TOTAL, seat 1, everything':<56}{running:>10.2f}")
    print()


# --------------------------------------------------------------------- plan --
def show_plan(client: httpx.Client, name: str, volume_gb: int, ssh_key_name: Optional[str]) -> int:
    volume_name = f"{name}-data"
    print(f"Plan for {name} ({SERVER_TYPE}, {LOCATION})")
    print()

    try:
        key = resolve_ssh_key(client, ssh_key_name)
        print(f"  ssh key   USE       {key['name']}  ({key.get('fingerprint', '?')})")
    except HetznerError as exc:
        print(f"  ssh key   PROBLEM   {exc}")

    firewall = find_by_name(client, "firewalls", FIREWALL_NAME)
    if firewall:
        inbound = [r for r in firewall.get("rules", []) if r.get("direction") == "in"]
        print(f"  firewall  EXISTS    {FIREWALL_NAME} "
              f"(id {firewall['id']}, {len(inbound)} inbound rules)")
        if inbound:
            print("            [warn]  it has inbound rules -- this design expects ZERO")
    else:
        print(f"  firewall  CREATE    {FIREWALL_NAME} -- deny all inbound, allow all outbound")

    volume = find_by_name(client, "volumes", volume_name)
    if volume:
        print(f"  volume    EXISTS    {volume_name} "
              f"(id {volume['id']}, {volume['size']} GB, {volume['location']['name']})")
    else:
        print(f"  volume    CREATE    {volume_name} -- {volume_gb} GB, {LOCATION}, unformatted")

    server = find_by_name(client, "servers", name)
    if server:
        ip = (server.get("public_net", {}).get("ipv4") or {}).get("ip", "-")
        print(f"  server    EXISTS    {name} (id {server['id']}, {server['status']}, {ip})")
    else:
        print(f"  server    CREATE    {name} -- {SERVER_TYPE}, {LOCATION}, "
              f"image {PLACEHOLDER_IMAGE} (placeholder)")

    print_cost_table(fetch_prices(client), volume_gb)
    print("  Nothing was created. Re-run with --apply to build it.")
    return 0


# -------------------------------------------------------------------- apply --
def do_apply(client: httpx.Client, name: str, volume_gb: int, ssh_key_name: Optional[str]) -> int:
    volume_name = f"{name}-data"
    key = resolve_ssh_key(client, ssh_key_name)
    print(f"ssh key    : {key['name']} ({key.get('fingerprint', '?')})")

    # ---- firewall --------------------------------------------------------- #
    # ZERO inbound rules, on purpose, and this is the single most important
    # security decision in the build. Not "3389 from my IP" -- deny everything.
    # Every route into this box is Tailscale, which is outbound-only from the
    # VM's point of view: it dials out to the coordination server and needs no
    # listening port at all. A Windows machine with 3389 reachable from the
    # public internet is found by scanners within minutes of the IP going live,
    # and it gets found whether or not the password is any good.
    #
    # A Hetzner firewall with no `direction: out` rules leaves outbound traffic
    # unrestricted, which is what we want -- so an empty rule set means exactly
    # "nothing in, everything out".
    firewall = find_by_name(client, "firewalls", FIREWALL_NAME)
    if firewall:
        print(f"firewall   : exists (id {firewall['id']})")
    else:
        created = call(client, "POST", "/firewalls", {
            "name": FIREWALL_NAME,
            "rules": [],
            "labels": LABELS,
        })
        firewall = created["firewall"]
        for act in created.get("actions") or []:
            wait_for_action(client, act, f"/firewalls/{firewall['id']}")
        print(f"firewall   : created (id {firewall['id']}) -- 0 inbound rules")

    # ---- volume ----------------------------------------------------------- #
    # Deliberately created WITHOUT a filesystem. `format: ext4` would be wasted
    # work: Windows reformats this as NTFS the first time it initialises D:, and
    # an ext4 signature on it only makes the disk look confusing in Disk
    # Management until someone clears it.
    volume = find_by_name(client, "volumes", volume_name)
    if volume:
        print(f"volume     : exists (id {volume['id']}, {volume['size']} GB)")
        if volume["size"] != volume_gb:
            print(f"             [warn] size is {volume['size']} GB, plan says {volume_gb} GB "
                  f"-- Hetzner volumes can grow but never shrink; not touching it")
    else:
        created = call(client, "POST", "/volumes", {
            "name": volume_name,
            "size": volume_gb,
            "location": LOCATION,
            "automount": False,
            "labels": LABELS,
        })
        volume = created["volume"]
        wait_for_actions(client, created, f"/volumes/{volume['id']}")
        print(f"volume     : created (id {volume['id']}, {volume_gb} GB, unformatted)")

    # ---- server ----------------------------------------------------------- #
    server = find_by_name(client, "servers", name)
    if server:
        print(f"server     : exists (id {server['id']}, {server['status']})")
    else:
        created = call(client, "POST", "/servers", {
            "name": name,
            "server_type": SERVER_TYPE,
            "location": LOCATION,
            "image": PLACEHOLDER_IMAGE,
            "start_after_create": True,
            "ssh_keys": [key["id"]],
            "firewalls": [{"firewall": firewall["id"]}],
            "volumes": [volume["id"]],
            "automount": False,
            "public_net": {"enable_ipv4": True, "enable_ipv6": True},
            "labels": LABELS,
        })
        server = created["server"]
        print(f"server     : creating (id {server['id']}) -- "
              f"waiting for create, start, volume attach, firewall apply")
        wait_for_actions(client, created, f"/servers/{server['id']}")
        print(f"server     : created (id {server['id']})")

    # Re-read both resources. The create response is a snapshot taken before the
    # actions finished, so its status and attachment fields are already stale.
    server = call(client, "GET", f"/servers/{server['id']}")["server"]
    volume = call(client, "GET", f"/volumes/{volume['id']}")["volume"]
    firewall = call(client, "GET", f"/firewalls/{firewall['id']}")["firewall"]

    # ---- reconcile -------------------------------------------------------- #
    # Only reached on a re-run against a server that already existed, or if the
    # attach/apply were not part of this create.
    if volume.get("server") != server["id"]:
        print("volume     : not attached -- attaching")
        resp = call(client, "POST", f"/volumes/{volume['id']}/actions/attach", {
            "server": server["id"],
            "automount": False,
        })
        wait_for_action(client, resp.get("action"), f"/volumes/{volume['id']}")
        volume = call(client, "GET", f"/volumes/{volume['id']}")["volume"]
        print("volume     : attached")

    applied = {
        (a.get("server") or {}).get("id")
        for a in (firewall.get("applied_to") or [])
        if a.get("type") == "server"
    }
    if server["id"] not in applied:
        print("firewall   : not applied to this server -- applying")
        resp = call(client, "POST", f"/firewalls/{firewall['id']}/actions/apply_to_resources", {
            "apply_to": [{"type": "server", "server": {"id": server["id"]}}],
        })
        for act in resp.get("actions") or []:
            wait_for_action(client, act, f"/firewalls/{firewall['id']}")
        print("firewall   : applied")

    ipv4 = (server.get("public_net", {}).get("ipv4") or {}).get("ip", "")
    print_next_steps(server, volume, key, ipv4)
    return 0


def print_next_steps(server: Dict[str, Any], volume: Dict[str, Any],
                     key: Dict[str, Any], ipv4: str) -> None:
    device = f"/dev/disk/by-id/scsi-0HC_Volume_{volume['id']}"
    print()
    print("=" * 74)
    print(f"  {server['name']} is up.  IPv4 {ipv4}")
    print(f"  data volume device on the rescue system: {device}")
    print("=" * 74)
    print("""
The infrastructure is done. Windows 11 is installed by hand from the rescue
system -- Hetzner Cloud's ISO library is public-only (Windows Server and virtio
only, no Windows 11) and it takes no private ISO uploads, so QEMU inside rescue
writes the install straight to /dev/sda.

Full runbook, including the virtio driver step people fail at:
    C:\\1Claude\\scripts\\newpc\\CLOUD-DESKTOP.md

1. Enable rescue and reboot into it. Run these in Git Bash, not PowerShell 5.1 --
   PS 5.1 re-splits the embedded JSON quoting and the request goes out malformed:
""")
    print(f"""    curl -sS -X POST "https://api.hetzner.cloud/v1/servers/{server['id']}/actions/enable_rescue" \\
      -H "Authorization: Bearer $HETZNER_API_TOKEN" -H "Content-Type: application/json" \\
      -d '{{"type":"linux64","ssh_keys":[{key['id']}]}}'

    curl -sS -X POST "https://api.hetzner.cloud/v1/servers/{server['id']}/actions/reset" \\
      -H "Authorization: Bearer $HETZNER_API_TOKEN"

2. SSH in. The host key WILL have changed -- rescue is a different system:

    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@{ipv4}

3. In rescue, park the ISOs on the data volume. It gets reformatted as D: later,
   so using it as scratch costs nothing, and the rescue root is a small ramdisk
   that a 6 GB Windows ISO will fill:

    apt update && apt install -y qemu-system-x86 qemu-utils
    mkfs.ext4 -F {device}
    mkdir -p /mnt/iso && mount {device} /mnt/iso
    curl -L -o /mnt/iso/virtio-win.iso \\
      https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
    #  The Windows 11 ISO download link from microsoft.com is session-signed and
    #  cannot be curl'd. Download it on DESKTOP1, then push it up:
    #     scp Win11_24H2_English_x64.iso root@{ipv4}:/mnt/iso/win11.iso

4. Run the installer VM. /dev/sda is the target; the data volume is NOT handed to
   QEMU, so the installer sees exactly one disk and cannot pick the wrong one:

    qemu-system-x86_64 -machine q35 -smp 4 -m 8192 \\
      -drive file=/dev/sda,format=raw,if=virtio,cache=none \\
      -drive file=/mnt/iso/win11.iso,media=cdrom,index=1 \\
      -drive file=/mnt/iso/virtio-win.iso,media=cdrom,index=2 \\
      -boot d -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \\
      -device usb-ehci -device usb-tablet -vnc 127.0.0.1:0 -monitor stdio

   Add `-enable-kvm -cpu host` ONLY if /dev/kvm exists on the rescue system.
   Check with `ls -l /dev/kvm` first -- see the runbook.

5. From your own machine, tunnel to that VNC and point a viewer at localhost:5900:

    ssh -N -L 5900:127.0.0.1:5900 root@{ipv4}

The Windows installer will report that it can find no disk until you use
"Load driver" and point it at viostor for w11/amd64 on the virtio CD. That is
step 4.4 in the runbook, and it is where this goes wrong for almost everyone.
""")


# ------------------------------------------------------------------ destroy --
def do_destroy(client: httpx.Client, name: str) -> int:
    volume_name = f"{name}-data"
    server = find_by_name(client, "servers", name)
    volume = find_by_name(client, "volumes", volume_name)
    firewall = find_by_name(client, "firewalls", FIREWALL_NAME)

    print("This will PERMANENTLY delete:")
    print(f"  server   {name:<24} {'(id ' + str(server['id']) + ')' if server else '-- not found'}")
    print(f"  volume   {volume_name:<24} {'(id ' + str(volume['id']) + ')' if volume else '-- not found'}")
    print(f"  firewall {FIREWALL_NAME:<24} {'(id ' + str(firewall['id']) + ')' if firewall else '-- not found'}")
    print()
    print("The volume's contents (everything on D:) go with it, and Hetzner keeps no copy.")
    print("Snapshots and images are NOT deleted by this command.")
    print()

    if not sys.stdin.isatty():
        print("ERROR: --destroy needs an interactive terminal to confirm.", file=sys.stderr)
        return 1
    typed = input(f"Type the server name ({name}) to confirm: ").strip()
    if typed != name:
        print("Names do not match. Nothing was deleted.")
        return 1

    if server:
        resp = call(client, "DELETE", f"/servers/{server['id']}")
        wait_for_action(client, resp.get("action"), f"/servers/{server['id']}")
        print(f"server     : deleted ({name})")

    if volume:
        # Deleting the server detaches the volume, but that detach is its own
        # action and the delete below fails with `resource_in_use` if it lands
        # first. Poll until Hetzner agrees the volume is free.
        deadline = time.time() + 120
        while True:
            current = call(client, "GET", f"/volumes/{volume['id']}")["volume"]
            if current.get("server") is None:
                break
            if time.time() > deadline:
                print("ERROR: volume is still attached after 120s; detach and delete it "
                      "by hand in the Hetzner console.", file=sys.stderr)
                return 1
            time.sleep(3)
        call(client, "DELETE", f"/volumes/{volume['id']}")
        print(f"volume     : deleted ({volume_name})")

    if firewall:
        # Refetch: applied_to is stale now that the server is gone. A firewall
        # still protecting another seat's server must survive this teardown.
        firewall = call(client, "GET", f"/firewalls/{firewall['id']}")["firewall"]
        still_used = firewall.get("applied_to") or []
        if still_used:
            print(f"firewall   : KEPT ({FIREWALL_NAME}) -- still applied to "
                  f"{len(still_used)} other resource(s)")
        else:
            call(client, "DELETE", f"/firewalls/{firewall['id']}")
            print(f"firewall   : deleted ({FIREWALL_NAME})")

    print()
    print("Done. Hetzner bills hourly, so charges for these resources stop at deletion.")
    return 0


# --------------------------------------------------------------------- main --
def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--apply", action="store_true",
                    help="actually create resources (default is a dry run)")
    ap.add_argument("--destroy", action="store_true",
                    help="delete server, volume and firewall (asks you to type the name)")
    ap.add_argument("--dry-run", action="store_true",
                    help="show the plan and the cost, create nothing -- this is the default")
    ap.add_argument("--name", default=SERVER_NAME_DEFAULT,
                    help=f"server name (default {SERVER_NAME_DEFAULT}); "
                         f"the volume is always <name>-data")
    ap.add_argument("--volume-gb", type=int, default=VOLUME_SIZE_GB,
                    help=f"data volume size in GB (default {VOLUME_SIZE_GB})")
    ap.add_argument("--ssh-key",
                    help="name of the Hetzner SSH key to inject; "
                         "required if the project has more than one")
    args = ap.parse_args()

    if args.apply and args.destroy:
        print("ERROR: --apply and --destroy are mutually exclusive.", file=sys.stderr)
        return 2

    token = os.environ.get("HETZNER_API_TOKEN", "").strip()
    if not token:
        print(
            "ERROR: $HETZNER_API_TOKEN is not set. Run this through Doppler:\n"
            "  doppler run -p grotap -c prd -- python scripts/newpc/cloud-desktop-provision.py",
            file=sys.stderr,
        )
        return 1

    try:
        with _client(token) as client:
            if args.destroy:
                return do_destroy(client, args.name)
            if args.apply:
                return do_apply(client, args.name, args.volume_gb, args.ssh_key)
            return show_plan(client, args.name, args.volume_gb, args.ssh_key)
    except HetznerError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    except httpx.HTTPError as exc:
        print(f"ERROR: HTTP failure talking to {API}: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrupted. Re-run the same command -- the script is idempotent and "
              "will pick up whatever already exists.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())

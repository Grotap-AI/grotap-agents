"""Provision agent-30/agent-31 (Team 3 — Grok 4.5 executors) in OpenAgents.grotapai.

Owner-approved 2026-07-12: 2x cpx22 in FSN1 (same DC as GEX131-1 / llm-gpu-02) so they
(cpx21 is not offered in FSN1 — cpx22 2c/4GB EUR22.99/mo is the closest; EU premium)
can attach to the pre-staged team2-llm-lan Cloud Network (id 12438415, eu-central) —
the Ashburn team2 boxes cannot. Uses HETZNER_FARM_API_TOKEN. Idempotent.

Run: doppler run -p grotap -c prd -- python provision-team3.py
"""
import json
import os
import time
import urllib.error
import urllib.request

TOK = os.environ["HETZNER_FARM_API_TOKEN"]
PUBKEY = (
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJiGJUlEkAootc2g9LUmd5dU7C6EjxSS+Dk1rH0zdMOp "
    "grotap-agent-farm-r2-20260705"
)
SERVERS = ["agent-30", "agent-31"]
NETWORK_ID = 12438415  # team2-llm-lan (10.0.0.0/16, cloud subnet 10.0.2.0/24)


def api(method: str, path: str, body: dict | None = None):
    req = urllib.request.Request(
        "https://api.hetzner.cloud/v1" + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": f"Bearer {TOK}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {e.read().decode()[:400]}")


# 1. SSH key
keys = api("GET", "/ssh_keys")["ssh_keys"]
if any(k["name"] == "grotap-agents" for k in keys):
    print("ssh key grotap-agents: exists")
else:
    api("POST", "/ssh_keys", {"name": "grotap-agents", "public_key": PUBKEY})
    print("ssh key grotap-agents: created")

# 2. Servers (fsn1 + private network attach at create time)
existing = {s["name"]: s for s in api("GET", "/servers")["servers"]}
for name in SERVERS:
    if name in existing:
        print(f"{name}: exists ip={existing[name]['public_net']['ipv4']['ip']}")
        continue
    res = api("POST", "/servers", {
        "name": name,
        "server_type": "cpx22",
        "location": "fsn1",
        "image": "ubuntu-24.04",
        "ssh_keys": ["grotap-agents"],
        "networks": [NETWORK_ID],
        "labels": {"team": "team3", "role": "grok-executor"},
        "start_after_create": True,
    })
    ip = res["server"]["public_net"]["ipv4"]["ip"]
    print(f"{name}: CREATED id={res['server']['id']} ip={ip}")

# 3. Wait for running + report private IPs
servers = {}
for _ in range(30):
    servers = {s["name"]: s for s in api("GET", "/servers")["servers"]}
    states = {n: servers[n]["status"] for n in SERVERS if n in servers}
    print("status:", states)
    if all(v == "running" for v in states.values()) and len(states) == len(SERVERS):
        break
    time.sleep(10)

for n in SERVERS:
    s = servers[n]
    priv = [p["ip"] for p in s.get("private_net", [])]
    print(f"FINAL {n}: {s['status']} ip={s['public_net']['ipv4']['ip']} private={priv}")

"""Provision agent-40/agent-41 (Team 4 — GPT-5.6 executors) in OpenAgents.grotapai.

Owner-approved 2026-07-13 ("execute all of your plan", docs/GPT56_SOL_TEAM4_PLAN.md):
2x cpx21 in ASH (Ashburn) — inference is OpenRouter-hosted (openai/gpt-5.6-*), so no
GPU-LAN adjacency needed and Ashburn is ~1/3 the FSN1 price. No private network attach
(team2-llm-lan is eu-central; ash cannot join — same reason team2 boxes aren't on it).
Uses HETZNER_FARM_API_TOKEN. Idempotent.

Run: doppler run -p grotap -c prd -- python provision-team4.py
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
SERVERS = ["agent-40", "agent-41"]


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

# 2. Servers (ash, public-only)
existing = {s["name"]: s for s in api("GET", "/servers")["servers"]}
for name in SERVERS:
    if name in existing:
        print(f"{name}: exists ip={existing[name]['public_net']['ipv4']['ip']}")
        continue
    res = api("POST", "/servers", {
        "name": name,
        "server_type": "cpx21",
        "location": "ash",
        "image": "ubuntu-24.04",
        "ssh_keys": ["grotap-agents"],
        "labels": {"team": "team4", "role": "gpt-executor"},
        "start_after_create": True,
    })
    ip = res["server"]["public_net"]["ipv4"]["ip"]
    print(f"{name}: CREATED id={res['server']['id']} ip={ip}")

# 3. Wait for running
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
    print(f"FINAL {n}: {s['status']} id={s['id']} ip={s['public_net']['ipv4']['ip']}")

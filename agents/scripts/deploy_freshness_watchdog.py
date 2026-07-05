#!/usr/bin/env python3
"""Deploy-freshness watchdog — cron */5 on agent-06 (CASE-20260704-RLWAY1).

Detects silent Railway non-deploys of grotap-backend: after a master push that
touches backend/, the live api.grotap.com/health git_sha must catch up within
20 minutes, else a P1 HI hold is filed. Railway bakes RAILWAY_GIT_COMMIT_SHA
into GitHub-triggered deploys; /health exposes it as git_sha.

Freshness logic (avoids false alarms on non-backend pushes):
  fresh  <- live git_sha == origin/master SHA
  fresh  <- git tree hash of live_sha:backend == origin/master:backend
            (commits since the live one didn't touch backend/)
  wait   <- newest backend-touching commit is younger than 20 min
  ALERT  <- otherwise (also when live git_sha is missing/unknown 20+ min after
            a backend commit — the marker itself failed to ship)

The orchestrator service is intentionally NOT checked: it ships via
`railway up` only (no GitHub auto-deploy), so master-vs-live drift is normal.

Dedupe: alerts once per stale master SHA, plus a 6h cooldown.
Stdlib only; no secrets needed (public health endpoint + local git clone).
"""
import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone

API_HEALTH = "https://api.grotap.com/health"
HI_API = "https://api.grotap.com/human-intervention/"
REPO = os.path.expanduser("~/grotap-platform")
STATE_FILE = os.path.expanduser("~/automation/.deploy_freshness_state.json")
FRESHNESS_WINDOW_S = 20 * 60
COOLDOWN_S = 6 * 3600


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git(*args: str) -> str:
    out = subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {out.stderr.strip()[:300]}")
    return out.stdout.strip()


def load_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(state: dict) -> None:
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def live_git_sha() -> str:
    req = urllib.request.Request(API_HEALTH, headers={"User-Agent": "deploy-watchdog/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return (json.loads(r.read()).get("git_sha") or "unknown").strip()


def file_hold(master_sha: str, live_sha: str, age_min: int, state: dict) -> None:
    now_ts = datetime.now(timezone.utc).timestamp()
    if state.get("alerted_sha") == master_sha or now_ts - state.get("alerted_at", 0) < COOLDOWN_S:
        print(f"[{now_utc()}] ALERT SUPPRESSED (dedupe/cooldown) master={master_sha[:8]}")
        return
    body = json.dumps({
        "task_id": f"deploy-freshness-{master_sha[:12]}",
        "task_title": f"P1: backend deploy stale — master {master_sha[:8]} not live after {age_min} min",
        "category": "deploy_failure",
        "description": (
            f"api.grotap.com/health reports git_sha={live_sha[:12] or 'unknown'} but origin/master is "
            f"{master_sha} (backend/ changed, pushed {age_min} min ago). Railway GitHub auto-deploy "
            f"likely failed silently again (see CASE-20260704-RLWAY1). Check Railway deployments for "
            f"grotap-backend; stopgap: `doppler run -p grotap -c prd -- railway up --service grotap-backend` "
            f"from backend/.\n\nSource: deploy_freshness_watchdog.py on agent-06 (cron */5). "
            f"Re-fires once per stale SHA / 6h."
        ),
        "priority": "high",
        "server_name": "agent-06",
        "created_by": "deploy-watchdog",
    }).encode()
    req = urllib.request.Request(
        HI_API, data=body,
        headers={"Content-Type": "application/json", "User-Agent": "deploy-watchdog/1.0"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        if 200 <= r.status < 300:
            state["alerted_sha"] = master_sha
            state["alerted_at"] = now_ts
            print(f"[{now_utc()}] HOLD FILED — master {master_sha[:8]} stale, live {live_sha[:8]}")


def main() -> int:
    state = load_state()
    git("fetch", "origin", "master", "--quiet")
    master_sha = git("rev-parse", "origin/master")
    master_backend_tree = git("rev-parse", "origin/master:backend")
    backend_commit_ts = int(git("log", "-1", "--format=%ct", "origin/master", "--", "backend"))
    age_s = int(datetime.now(timezone.utc).timestamp()) - backend_commit_ts

    try:
        live = live_git_sha()
    except Exception as exc:
        # Health endpoint down is the pipeline monitor's alert, not ours.
        print(f"[{now_utc()}] health unreachable ({exc}) — skipping")
        return 0

    if live == master_sha:
        print(f"[{now_utc()}] FRESH — live == master {master_sha[:8]}")
        state.pop("alerted_sha", None)
        save_state(state)
        return 0

    if live not in ("", "unknown"):
        try:
            if git("rev-parse", f"{live}:backend") == master_backend_tree:
                print(f"[{now_utc()}] FRESH — backend tree unchanged since live {live[:8]}")
                state.pop("alerted_sha", None)
                save_state(state)
                return 0
        except RuntimeError:
            print(f"[{now_utc()}] live sha {live[:8]} unknown to repo — treating as stale")

    if age_s < FRESHNESS_WINDOW_S:
        print(f"[{now_utc()}] WAIT — backend commit {age_s // 60} min old, window {FRESHNESS_WINDOW_S // 60} min")
        return 0

    file_hold(master_sha, live, age_s // 60, state)
    save_state(state)
    return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Pipeline failure monitor — cron */10 on agent-06.

Checks the dispatch machinery end-to-end and files an HI hold (category
dispatch_failure) when something is wrong. Stdlib only; DB access via psql
using $DATABASE_URL, secrets injected by `doppler run` in the cron line.

Checks:
  backend_health       GET https://api.grotap.com/health == 200
  orchestrator_health  GET $ORCHESTRATOR_URL/health == 200
  failed_dispatches    dispatch_log failed in the last 15 min
  stuck_queue          dispatch rows queued/dispatched >15 min, never started
  stale_attempts       dispatch rows active >2h (exec hard cap is 1h)
  stale_executing      cases executing with no update >3h

Dedupe: per-check cooldown (6h) via a local state file, so a persistent
failure alerts at most 4x/day instead of every 10 minutes.
"""
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

API = "https://api.grotap.com"
ORCH = os.environ.get("ORCHESTRATOR_URL", "").rstrip("/")
STATE_FILE = os.path.expanduser("~/automation/.pipeline_monitor_state.json")
COOLDOWN_S = 6 * 3600


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


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


def http_status(url: str, timeout: int = 15) -> int:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "pipeline-monitor/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def psql(sql: str) -> list[list[str]]:
    """Run a query against the control-plane DB; rows as lists of strings."""
    out = subprocess.run(
        ["psql", os.environ["DATABASE_URL"], "-t", "-A", "-F", "|", "-c", sql],
        capture_output=True, text=True, timeout=60,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip()[:500])
    return [line.split("|") for line in out.stdout.strip().splitlines() if line.strip()]


def file_hold(check: str, title: str, description: str, state: dict) -> bool:
    """Create an HI hold unless this check alerted within the cooldown window."""
    last = state.get(check, 0)
    now_ts = datetime.now(timezone.utc).timestamp()
    if now_ts - last < COOLDOWN_S:
        print(f"[{now_utc()}] {check}: ALERT SUPPRESSED (cooldown) — {title}")
        return False
    body = json.dumps({
        "task_id": f"pipeline-monitor-{check}",
        "task_title": title,
        "category": "dispatch_failure",
        "description": description + "\n\nSource: pipeline_failure_monitor.py on agent-06 (runs every 10 min). What needs to happen? Investigate and clear the failure; this alert re-fires every 6h while the condition persists.",
        "priority": "high",
        "server_name": "agent-06",
        "created_by": "pipeline-monitor",
    }).encode()
    req = urllib.request.Request(
        f"{API}/human-intervention/", data=body,
        headers={"Content-Type": "application/json", "User-Agent": "pipeline-monitor/1.0"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            ok = 200 <= r.status < 300
    except Exception as exc:
        print(f"[{now_utc()}] {check}: FAILED TO FILE HOLD: {exc}")
        return False
    if ok:
        state[check] = now_ts
        print(f"[{now_utc()}] {check}: HOLD FILED — {title}")
    return ok


def main() -> int:
    state = load_state()
    problems = 0

    # 1+2 — service health
    for check, name, url in (
        ("backend-health", "Backend API", f"{API}/health"),
        ("orchestrator-health", "Dispatch orchestrator", f"{ORCH}/health" if ORCH else ""),
    ):
        if not url:
            continue
        code = http_status(url)
        if code != 200:
            problems += 1
            file_hold(check, f"{name} health check failing (HTTP {code or 'unreachable'})",
                      f"{url} returned HTTP {code or 'no response'} at {now_utc()}.", state)
        else:
            print(f"[{now_utc()}] {check}: ok")

    # 3-6 — DB-backed checks
    queries = {
        "failed-dispatches": (
            "SELECT case_id, agent_server FROM pipeline_dispatch_log "
            "WHERE status='failed' AND completed_at > now() - interval '15 minutes'",
            "Dispatch failures in the last 15 minutes",
        ),
        "stuck-queue": (
            "SELECT case_id, status FROM pipeline_dispatch_log "
            "WHERE status IN ('pending','queued','dispatched') AND started_at IS NULL "
            "AND dispatched_at < now() - interval '15 minutes' "
            "AND dispatched_at > now() - interval '24 hours'",
            "Dispatches queued >15 min without starting (orchestrator not picking up)",
        ),
        "stale-attempts": (
            "SELECT case_id, agent_server FROM pipeline_dispatch_log "
            "WHERE status='active' AND started_at < now() - interval '2 hours'",
            "Dispatch attempts active >2h (exec cap is 1h — likely wedged)",
        ),
        "stale-executing": (
            "SELECT case_id FROM pipeline_cases "
            "WHERE status='executing' AND updated_at < now() - interval '3 hours' "
            "AND updated_at > now() - interval '7 days'",
            "Cases stuck in executing with no update for >3h",
        ),
    }
    try:
        for check, (sql, title) in queries.items():
            rows = psql(sql)
            if rows:
                problems += 1
                detail = "\n".join("  - " + " on ".join(filter(None, r)) for r in rows[:15])
                file_hold(check, f"{title} ({len(rows)})",
                          f"{title}:\n{detail}\n\nDetected at {now_utc()}.", state)
            else:
                print(f"[{now_utc()}] {check}: ok")
    except Exception as exc:
        problems += 1
        file_hold("monitor-db-error", "Pipeline monitor cannot query control-plane DB",
                  f"psql failed: {exc}", state)

    save_state(state)
    print(f"[{now_utc()}] run complete — {problems} problem(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

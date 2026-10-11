#!/bin/bash
# ssh-key-for.twin-check.sh — Fail when the ssh-key-for.sh TWIN copies drift.
#
# ssh-key-for.sh is deliberately duplicated: callers live in grotap-platform
# (dispatch.sh, config.sh, update-fleet-cli.sh, reconcile_dispatch.py) and in
# grotap-agents (health-monitor.sh, sync-all-agents.sh, setup-agent06.sh), and
# neither repo reaches across a guessed checkout path. Duplication is the
# design; SILENT duplication is the defect.
#
# Why drift here is invisible without this check: consumers resolve the key
# with `KEY="$(bash .../ssh-key-for.sh "$target")"` and then `ssh -i "$KEY"`.
# A host missing from the stale copy's table does not raise — it resolves to
# the RETIRED shared fleet key (with only a stderr WARNING, which many callers
# discard) and the connection simply fails. health-monitor.sh then logs "AGENT UNREACHABLE", so a credential fault
# is miscategorised as a dead box: the only symptom points at the wrong
# subsystem, which is why drift here could run indefinitely unnoticed.
# Status 2026-09-20: the copies are in sync. This check keeps them that way.
#
# This check compares the two copies against EACH OTHER. It never compares a
# file to itself and it never "skips": if it cannot find the twin repo it
# FAILS, because an unlocatable twin is the same unverified state as a drifted
# one for a file whose entire contract is "byte-identical in two places".
#
# Run (from either repo):
#     bash agents/scripts/ssh-key-for.twin-check.sh
# Override twin discovery (e.g. single-repo CI that checks out the other repo
# somewhere else):
#     SSH_KEY_FOR_TWIN_REPO=/path/to/other/repo bash .../ssh-key-for.twin-check.sh
#
# TWIN FILE: this script is itself kept byte-identical in both repos and checks
# itself, so a one-sided edit to the checker is caught by the checker.
set -uo pipefail

# Files that MUST be byte-identical across the two repos, repo-root relative.
# Deliberately NOT a glob over agents/scripts: orchestrator-run.sh,
# review-gate-cron.sh and review-gate-task.md are knowingly divergent copies
# owned by other programmes. Adding them here would make this check red on day
# one and get it switched off. Keep this list to files with a real
# byte-identical contract.
TWIN_FILES=(
  "agents/scripts/ssh-key-for.sh"
  "agents/scripts/ssh-key-for.test.sh"
  "agents/scripts/ssh-key-for.twin-check.sh"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- locate THIS repo root ---------------------------------------------------
HERE="$(cd "$SCRIPT_DIR/../.." && pwd)"
if git -C "$HERE" rev-parse --show-toplevel >/dev/null 2>&1; then
  HERE="$(git -C "$HERE" rev-parse --show-toplevel)"
fi
# Re-resolve through `cd`/`pwd` so HERE and TWIN are in the SAME path syntax.
# On Windows/MSYS `git rev-parse --show-toplevel` answers `C:/1Claude` while
# `cd .. && pwd` answers `/c/1Claude`. Those are the same directory, so a raw
# string compare below would let the self-comparison guard through and the
# check would diff every file against ITSELF and report PASS -- the exact
# vacuous green this script exists to prevent. Proven: with HERE from git and
# SSH_KEY_FOR_TWIN_REPO pointing at the same checkout, the guard did not fire.
HERE="$(cd "$HERE" && pwd)"

# --- locate the TWIN repo root -----------------------------------------------
# grotap-platform is checked out INSIDE grotap-agents on the workstation and on
# the fleet boxes (<agents>/platform), so the two directions are:
#   agents  -> $HERE/platform
#   platform-> $(dirname $HERE)
# An explicit override wins, for checkouts that are not nested that way.
TWIN=""
if [[ -n "${SSH_KEY_FOR_TWIN_REPO:-}" ]]; then
  TWIN="$SSH_KEY_FOR_TWIN_REPO"
else
  for cand in "$HERE/platform" "$(dirname "$HERE")"; do
    [[ -d "$cand" ]] || continue
    [[ -f "$cand/agents/scripts/ssh-key-for.sh" ]] || continue
    # Must be a DIFFERENT checkout, or we would diff a file against itself.
    [[ "$(cd "$cand" && pwd)" != "$HERE" ]] || continue
    TWIN="$(cd "$cand" && pwd)"
    break
  done
fi

# Normalise TWIN the same way as HERE. An explicit override arrives verbatim,
# so `SSH_KEY_FOR_TWIN_REPO=C:/1Claude` run from /c/1Claude would otherwise slip
# past the self-comparison guard on a pure string compare and diff every file
# against itself.
if [[ -n "$TWIN" && -d "$TWIN" ]]; then
  TWIN="$(cd "$TWIN" && pwd)"
fi

if [[ -z "$TWIN" ]]; then
  cat >&2 <<MSG
FAIL: ssh-key-for.sh twin repo not found.
  this repo: $HERE
  searched : $HERE/platform, $(dirname "$HERE")
  This check does not pass when it cannot compare. Check out the other repo
  (grotap-agents / grotap-platform) next to this one, or set
  SSH_KEY_FOR_TWIN_REPO to its root.
MSG
  exit 2
fi

# Refuse to "pass" by diffing a checkout against itself.
if [[ "$TWIN" == "$HERE" ]]; then
  echo "FAIL: twin resolved to this same repo ($HERE) — that comparison is vacuous." >&2
  exit 2
fi

echo "ssh-key-for twin check"
echo "  A: $HERE"
echo "  B: $TWIN"
echo

RC=0
for f in "${TWIN_FILES[@]}"; do
  a="$HERE/$f"
  b="$TWIN/$f"
  if [[ ! -f "$a" ]]; then
    printf '  MISSING  %s (absent in A: %s)\n' "$f" "$HERE"
    RC=1
    continue
  fi
  if [[ ! -f "$b" ]]; then
    printf '  MISSING  %s (absent in B: %s)\n' "$f" "$TWIN"
    RC=1
    continue
  fi
  if diff -u "$a" "$b" > /tmp/.twincheck.$$ 2>&1; then
    printf '  ok       %s\n' "$f"
  else
    printf '  DRIFT    %s\n' "$f"
    sed 's/^/           /' /tmp/.twincheck.$$
    RC=1
  fi
  rm -f /tmp/.twincheck.$$
done

echo
if [[ "$RC" -eq 0 ]]; then
  echo "PASS: all ${#TWIN_FILES[@]} twin files are byte-identical across the two repos."
else
  cat <<'MSG'
FAIL: the twin copies have drifted.

Do NOT assume either side is correct. The newer copy is usually grotap-platform
(that is where the per-host-key work lands first), but confirm with
  git -C <repo> log --oneline -- agents/scripts/ssh-key-for.sh
in BOTH repos before copying, then re-run this check.

Remember what drift costs here: a host missing from a copy's HOST_BY_IP table
does not error, it silently resolves to the retired shared fleet key.
MSG
fi
exit "$RC"

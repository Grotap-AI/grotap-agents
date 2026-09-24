#!/bin/bash
# fleet-load.sh — Read-only CPU / memory / disk sampler for the worker boxes (agent-02-claude…agent-06-claude).
#
# Why this exists: since 2026-09-15 every worker box runs TWO daemons — the agent tmux
# session used by dispatch.sh, and forgejo-runner (v13.1.0, HOST execution mode, capacity 2,
# unprivileged forge-runner user). Nothing on the fleet has ever collected host metrics
# (health-monitor.sh is liveness only: HTTP 200 checks plus an SSH "echo ok"), so there was
# no way to tell whether fleet execute and Forgejo CI starve each other during a CI burst.
#
# This script only READS. It writes nothing on the remote hosts, installs nothing, and
# starts no daemon. It is safe to run repeatedly and safe to leave running with --watch.
#
# Usage:
#   bash fleet-load.sh                  # one sample of every host
#   bash fleet-load.sh --watch 30       # resample every 30 seconds until Ctrl-C
#   bash fleet-load.sh --host agent-04-claude  # one host only (repeatable)
#   bash fleet-load.sh --log /path/to/fleet-load.log
#
# Exit status: 0 if every sampled host answered, 1 if any host was UNREACHABLE.
# In --watch mode the exit status reflects the last completed sweep.
set -uo pipefail

# ── Roster ───────────────────────────────────────────────────────────────────
# Source of truth is agents/SERVERS.md. Kept as name:ip so the script also works on a box
# with no ~/.ssh/config (e.g. agent-06-claude) as well as on the owner workstation.
HOSTS=(
  "agent-02-claude:5.161.74.39"
  "agent-03-claude:5.161.81.193"
  "agent-04-claude:178.156.222.220"
  "agent-05-claude:5.161.73.195"
  "agent-06-claude:5.161.53.103"
)

SSH_USER="${FLEET_SSH_USER:-root}"
SSH_KEY_DIR="${FLEET_SSH_KEY_DIR:-$HOME/.ssh}"
LOG="${FLEET_LOAD_LOG:-$HOME/logs/fleet-load.log}"
WATCH=0
SELECTED=()

# Until this date the agent fleet is hard-stopped by an Anthropic ORG USAGE CAP and the
# backend assign loop is disabled, so agent-side load reads near zero for reasons that have
# nothing to do with Forgejo. Any sample taken before this date is a forge-runner-only
# baseline — it is never evidence that the two daemons coexist safely under real load.
USAGE_CAP_UNTIL="2026-10-01"

# ── Argument parsing ─────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --watch)
      WATCH="${2:-}"
      case "$WATCH" in
        ""|*[!0-9]*) echo "fleet-load: --watch needs a whole number of seconds" >&2; exit 2 ;;
      esac
      shift 2
      ;;
    --host)
      [ -n "${2:-}" ] || { echo "fleet-load: --host needs a host name" >&2; exit 2; }
      SELECTED+=("$2"); shift 2
      ;;
    --log)
      [ -n "${2:-}" ] || { echo "fleet-load: --log needs a path" >&2; exit 2; }
      LOG="$2"; shift 2
      ;;
    -h|--help)
      sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "fleet-load: unknown argument '$1' (try --help)" >&2
      exit 2
      ;;
  esac
done

if [ "${#SELECTED[@]}" -gt 0 ]; then
  FILTERED=()
  for ENTRY in "${HOSTS[@]}"; do
    for WANT in "${SELECTED[@]}"; do
      [ "${ENTRY%%:*}" = "$WANT" ] && FILTERED+=("$ENTRY")
    done
  done
  [ "${#FILTERED[@]}" -gt 0 ] || { echo "fleet-load: no roster host matched --host" >&2; exit 2; }
  HOSTS=("${FILTERED[@]}")
fi

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# ── Remote probe ─────────────────────────────────────────────────────────────
# Fed to the remote shell on stdin; emits exactly one pipe-delimited record on stdout.
# Every command it runs is read-only.
# Field order: load1|load5|load15|cores|mem_total|mem_used|mem_free|mem_avail|
#              swap_used|disk_free_pct|runner_state|tmux_sessions|top3
PROBE=$(cat <<'PROBE_EOF'
set -u
read -r L1 L5 L15 _REST < /proc/loadavg
CORES=$(nproc 2>/dev/null || echo 0)
set -- $(free -m | awk '/^Mem:/{print $2, $3, $4, $7}')
MT=${1:-0}; MU=${2:-0}; MF=${3:-0}; MA=${4:-0}
SU=$(free -m | awk '/^Swap:/{print $3}')
DF=$(df -P / | awk 'NR==2{gsub("%","",$5); print 100-$5}')
RUNNER=$(systemctl is-active forgejo-runner 2>/dev/null || true)
[ -n "$RUNNER" ] || RUNNER=absent
TMUX=$(su - agent -c 'tmux ls' 2>/dev/null | cut -d: -f1 | paste -sd, - 2>/dev/null)
[ -n "$TMUX" ] || TMUX=none
# Two top iterations one second apart; only the second carries real instantaneous %CPU.
# A single ps snapshot reports a lifetime average, which on a 195-day-uptime box is noise.
TOP=$(top -b -n 2 -d 1 -w 512 2>/dev/null | awk '
  /^ *PID/ { blk++; for (i=1;i<=NF;i++) { if ($i=="%CPU") c=i; if ($i=="COMMAND") m=i } next }
  blk==2 && m>0 && NF>=m && $c+0 > 0 { printf "%s%s:%.0f%%", sep, $m, $c; sep=","; n++ }
  n>=3 { exit }
')
[ -n "$TOP" ] || TOP=idle
printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
  "$L1" "$L5" "$L15" "$CORES" "$MT" "$MU" "$MF" "$MA" "${SU:-0}" "${DF:-0}" "$RUNNER" "$TMUX" "$TOP"
PROBE_EOF
)

# Per-host SSH keys were added 2026-09-15; fall back to the shared fleet key, then to
# whatever ~/.ssh/config resolves on its own.
key_for() {
  if [ -f "$SSH_KEY_DIR/grotap_$1" ]; then
    printf '%s' "$SSH_KEY_DIR/grotap_$1"
  elif [ -f "$SSH_KEY_DIR/grotap_agents" ]; then
    printf '%s' "$SSH_KEY_DIR/grotap_agents"
  fi
}

# ── One sweep ────────────────────────────────────────────────────────────────
sweep() {
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  FAILED=0
  TOPLINES=""

  echo "fleet-load $TIMESTAMP  (read-only; log: $LOG)"
  printf '%-9s %-11s %-6s %-18s %-9s %-22s %-8s %-10s %s\n' \
    HOST STATE CORES "LOAD 1/5/15" PER-CORE "MEM MB u/f/avail" "SWAP MB" "DISK FREE" "RUNNER | TMUX"
  printf -- '%s\n' "-------------------------------------------------------------------------------------------------------------------------"

  for ENTRY in "${HOSTS[@]}"; do
    NAME="${ENTRY%%:*}"
    IP="${ENTRY##*:}"
    KEY="$(key_for "$NAME")"

    # StrictHostKeyChecking=yes — fail closed on host-key verification.
    # With `no`, this loop suppressed the warning a human probe would see and ran a
    # command on an UNVERIFIED destination. The exposure is
    # unauthenticated-destination command execution, NOT key disclosure: offering
    # public-key auth does not hand over the private half.
    # THIS ALONE DOES NOT CLOSE THE HOLE. The catch-all IP-glob Host blocks in
    # ~/.ssh/config that carry `StrictHostKeyChecking no` are the actual mitigation
    # and are owned elsewhere; this only stops ONE automated path from riding them.
    # SEEDING REQUIRED: every fleet host must have a correct known_hosts entry for
    # the address used here or the probe reports UNREACHABLE. As of 2026-09-15 four
    # fleet IPs present ed25519 keys that MISMATCH known_hosts, so those four break
    # first — a mismatch is a refusal, not a first-contact prompt.
    SSH_ARGS=(-o ConnectTimeout=8 -o StrictHostKeyChecking=yes -o BatchMode=yes)
    [ -n "$KEY" ] && SSH_ARGS+=(-i "$KEY")

    RAW=$(printf '%s\n' "$PROBE" | ssh "${SSH_ARGS[@]}" "$SSH_USER@$IP" "sh -s" 2>/dev/null | tail -1)

    if [ -z "$RAW" ]; then
      FAILED=1
      printf '%-9s %-11s %-6s %-18s %-9s %-22s %-8s %-10s %s\n' \
        "$NAME" "UNREACHABLE" "-" "-" "-" "-" "-" "-" "-"
      echo "[$TIMESTAMP] $NAME $IP state=UNREACHABLE" >> "$LOG"
      continue
    fi

    IFS='|' read -r L1 L5 L15 CORES MT MU MF MA SU DF RUNNER TMUX TOP <<< "$RAW"

    PERCORE=$(awk -v l="$L1" -v c="$CORES" 'BEGIN{ if (c+0>0) printf "%.2f", l/c; else print "?" }')
    # STATE is a coarse read on load1 per core: at or above 1.00 per core the box has no
    # spare CPU left for a second daemon's job.
    STATE=$(awk -v p="$PERCORE" 'BEGIN{ if (p+0>=1.00) print "SATURATED"; else if (p+0>=0.70) print "BUSY"; else if (p+0>=0.25) print "ACTIVE"; else print "IDLE" }')
    [ "$RUNNER" = "active" ] || STATE="$STATE*"

    printf '%-9s %-11s %-6s %-18s %-9s %-22s %-8s %-10s %s\n' \
      "$NAME" "$STATE" "$CORES" "$L1/$L5/$L15" "$PERCORE" "$MU/$MF/$MA" "$SU" "${DF}%" "$RUNNER | $TMUX"

    TOPLINES="$TOPLINES  $NAME  $TOP"$'\n'
    echo "[$TIMESTAMP] $NAME $IP state=$STATE cores=$CORES load=$L1/$L5/$L15 percore=$PERCORE mem_total=$MT mem_used=$MU mem_free=$MF mem_avail=$MA swap_used=$SU disk_free=${DF}% runner=$RUNNER tmux=$TMUX top=$TOP" >> "$LOG"
  done

  echo
  echo "Top processes by instantaneous CPU:"
  printf '%s' "$TOPLINES"
  echo "  (a STATE marked * means forgejo-runner is not active on that host)"

  # ── Interpretation caveat ──────────────────────────────────────────────────
  TODAY=$(date -u +%Y-%m-%d)
  if [ "$TODAY" \< "$USAGE_CAP_UNTIL" ]; then
    echo
    echo "CAVEAT — this is a forge-runner-only baseline, NOT an all-clear."
    echo "  The agent fleet is hard-stopped by an Anthropic ORG USAGE CAP until $USAGE_CAP_UNTIL and"
    echo "  the backend assign loop is disabled, so the agent half of the load is absent by"
    echo "  construction. A low reading here says nothing about whether an agent execute session"
    echo "  and forgejo-runner coexist under real load. Re-baseline after $USAGE_CAP_UNTIL with"
    echo "  dispatch running before drawing any conclusion about contention."
  fi

  return $FAILED
}

# ── Main ─────────────────────────────────────────────────────────────────────
RC=0
if [ "$WATCH" -gt 0 ]; then
  echo "fleet-load: sampling every ${WATCH}s — Ctrl-C to stop."
  trap 'echo; echo "fleet-load: stopped."; exit $RC' INT TERM
  while true; do
    sweep; RC=$?
    echo
    sleep "$WATCH"
  done
else
  sweep; RC=$?
fi
exit $RC

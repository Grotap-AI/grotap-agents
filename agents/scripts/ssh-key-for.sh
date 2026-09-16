#!/bin/bash
# ssh-key-for.sh — Print the SSH private key path to use for reaching <target>
# (a fleet host name like "agent-04" or its IP) as the CURRENT OS user, on the
# CURRENT host.
#
# TWIN FILE: dispatch.sh, config.sh, update-fleet-cli.sh, status-server.js and
# reconcile_dispatch.py live in grotap-platform, while health-monitor.sh and
# SERVERS.md (the fleet roster this table must stay in lockstep with) live in
# grotap-agents — two separate repos, both checked out on agent-06. Rather
# than have grotap-platform scripts reach across repos on a guessed checkout
# path, this file is kept byte-identical in both repos at
# agents/scripts/ssh-key-for.sh. Change one, copy to the other.
#
# Part of retiring the shared fleet key `grotap_agents` (phase 2b,
# 2026-09-16). Phase 1 (2026-09-16 04:01Z) provisioned per-target keys on
# agent-06 for both source users:
#   /home/agent/.ssh/grotap_from06_agent-0{2,3,4,5}
#   /root/.ssh/grotap_from06_agent-0{2,3,4,5}
# This resolver is the ONE place that knows how to turn a target into the
# right key path, so every caller (health-monitor.sh, dispatch.sh,
# update-fleet-cli.sh, reconcile_dispatch.py, status-server.js, ...) stops
# hardcoding the shared key and a later phase can delete it with no script
# changes required.
#
# Resolution order:
#   1. A per-host key at $HOME/.ssh/grotap_from<N>_<canonical-target>, where
#      <N> is derived from the CURRENT host's own short name (agent-06 ->
#      "06") and <canonical-target> is the resolved target (agent-02..05
#      today). $HOME reflects whichever OS user actually runs this — /root
#      under a root crontab, /home/agent under `sudo -u agent` — so root and
#      agent get the correct key from the exact same call, no extra flag.
#   2. Otherwise, the shared fleet key: $HOME/.ssh/grotap_agents. This
#      fallback is what makes it safe to roll the resolver out before every
#      per-host key pair exists, and to keep relying on it afterwards: any
#      target with no key yet (a jumpbox, a host this resolver doesn't run
#      on, maps-01/forge-01/GEX131 today) just keeps working off the shared
#      key until it, too, gets a per-host pair.
#
# Target/host-name table: an explicit table below, NOT a parse of
# agents/SERVERS.md. SERVERS.md is prose documentation (free-text rows, IPs
# embedded in bold Markdown, mixed with hosts that are never dispatch
# targets) meant for humans, and its exact formatting has already drifted
# more than once. Parsing it here would make key resolution depend on a doc
# file staying machine-parseable forever, i.e. the opposite of "safe to ship
# before every key exists." Keep this table in lockstep with the "Active
# dispatch pool" table in agents/SERVERS.md by hand — it only grows when a
# NEW per-host key pair is deliberately provisioned, which is already a
# manual step.
#
# Usage:
#   KEY="$(bash agents/scripts/ssh-key-for.sh <target-ip-or-host>)"
#   ssh -i "$KEY" root@<target> ...
#
# Exit status: 0 whenever a target argument was given — there is always a
# printable answer (the shared-key path, even if that file itself happens
# not to exist on disk; callers that care can stat it themselves). This
# keeps the resolver safe to call from `set -e` scripts via command
# substitution. Exit 2 only on a missing argument (misuse).
set -u

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "usage: ssh-key-for.sh <target-ip-or-host>" >&2
  exit 2
fi

SHARED_KEY="$HOME/.ssh/grotap_agents"

# --- IP -> canonical fleet host name (see header comment) -------------------
declare -A _SSH_KEY_FOR_HOST_BY_IP=(
  ["5.161.74.39"]="agent-02"
  ["5.161.81.193"]="agent-03"
  ["178.156.222.220"]="agent-04"
  ["5.161.73.195"]="agent-05"
  ["5.78.178.81"]="agent-06"
  ["87.99.148.22"]="agent-20"
  ["5.161.243.18"]="agent-21"
  ["167.233.59.142"]="agent-30"
  ["167.233.194.57"]="agent-31"
  ["178.156.219.232"]="agent-40"
  ["178.156.220.48"]="agent-41"
)

canon="$TARGET"
if [[ -n "${_SSH_KEY_FOR_HOST_BY_IP[$TARGET]:-}" ]]; then
  canon="${_SSH_KEY_FOR_HOST_BY_IP[$TARGET]}"
fi

# --- Which host is THIS resolver running on? ---------------------------------
# Only agent-06 has per-host keys as of phase 2a/2b (grotap_from06_*). Any
# other caller (the owner workstation, a future box) has no from-<N> keys to
# look for, so it falls straight through to the shared-key fallback.
_local_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
from_suffix=""
case "$_local_host" in
  agent-06|*agent-06*) from_suffix="06" ;;
esac

if [[ -n "$from_suffix" ]]; then
  candidate="$HOME/.ssh/grotap_from${from_suffix}_${canon}"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
fi

printf '%s\n' "$SHARED_KEY"
exit 0

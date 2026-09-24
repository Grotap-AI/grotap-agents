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
#   2. Otherwise a workstation-style per-host key at
#      $HOME/.ssh/grotap_<canonical-target> -- the naming the owner
#      workstation uses. Fleet boxes have none of these and fall past it.
#   3. Otherwise, the shared fleet key: $HOME/.ssh/grotap_agents. This
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
# Canonical names match agents/SERVERS.md after the 2026-09-21 Cloud rename
# and the 2026-09-23 GO rename of the jumpbox to prompt-01-claude.
# Per-host key FILES on disk still use the pre-rename basenames
# (grotap_from06_agent-02, grotap_claudecode-01, …). _SSH_KEY_FOR_LEGACY
# below finds those files. Do not map a released IP: Hetzner recycles them.
# Stale and unmapped: agent-06 Hillsboro 5.78.178.81; deleted agent-21/31/41,
# agent-30 (167.233.59.142), llm-gpu-02 (178.63.124.99).
# prompt-01-astra and agent-team-01-astra have no IP yet — do not add a row.
# Do not add agent-11-codex.
declare -A _SSH_KEY_FOR_HOST_BY_IP=(
  ["5.161.74.39"]="agent-02-claude"
  ["5.161.81.193"]="agent-03-claude"
  ["178.156.222.220"]="agent-04-claude"
  ["5.161.73.195"]="agent-05-claude"
  ["5.161.53.103"]="agent-06-claude"
  ["87.99.148.22"]="agent-10-codex"
  ["178.156.219.232"]="monitor-01-deepseek"
  ["5.161.107.80"]="maps-01"
  ["178.156.246.81"]="forge-01"
  ["178.156.209.112"]="prompt-01-claude"
  ["claudecode.grotap.com"]="prompt-01-claude"
  ["5.161.189.143"]="openreplay-01"
  ["supportagents.grotap.com"]="openreplay-01"
  ["178.156.199.83"]="openreplay-ai-support"
)

# Old bootstrap aliases → canonical Cloud name. Applied to a hostname lookup
# and also to a name that arrived via the IP table (the table is already
# canonical, so this is a no-op for those).
declare -A _SSH_KEY_FOR_ALIAS=(
  ["agent-02"]="agent-02-claude"
  ["agent-03"]="agent-03-claude"
  ["agent-04"]="agent-04-claude"
  ["agent-05"]="agent-05-claude"
  ["agent-06"]="agent-06-claude"
  ["agent-20"]="agent-10-codex"
  ["agent-40"]="monitor-01-deepseek"
  ["claudecode-01"]="prompt-01-claude"
  ["claude-code-01"]="prompt-01-claude"
  ["cobrowse-01"]="openreplay-01"
  ["grotap-cobrowse-01"]="openreplay-01"
  ["runner-01"]="openreplay-ai-support"
  ["grotap-runner-01"]="openreplay-ai-support"
)

# Canonical name → basename of the key file minted before the rename.
declare -A _SSH_KEY_FOR_LEGACY=(
  ["agent-02-claude"]="agent-02"
  ["agent-03-claude"]="agent-03"
  ["agent-04-claude"]="agent-04"
  ["agent-05-claude"]="agent-05"
  ["agent-06-claude"]="agent-06"
  ["agent-10-codex"]="agent-20"
  ["monitor-01-deepseek"]="agent-40"
  ["prompt-01-claude"]="claudecode-01"
  ["openreplay-01"]="cobrowse-01"
  ["openreplay-ai-support"]="runner-01"
)

# --- Canonicalize the target BEFORE the lookup -------------------------------
# This resolver is the single authority for key selection, so it must be safe
# for whatever token a caller happens to hold. Every non-canonical form below
# would otherwise MISS the table and fall through to the shared fleet key
# silently -- a caller that forgets to pre-clean its input gets fleet-wide
# credentials instead of an error. Callers still clean their own input as
# defense in depth; this is what makes that optional rather than load-bearing.
#   root@host       -> host        (an ssh destination, not a host name)
#   [host]:2222     -> host        (bracketed form with a port)
#   host:22         -> host        (port suffix)
#   Host.Example    -> host.example (DNS is case-insensitive; keys are lower)
# A bare IPv6 literal is left alone: its colons are the address, not a port.
# Trim first: a padded token (" agent-04 ", from a quoted shell variable or a
# hand-edited config line) would miss the table and fall through to the shared
# key -- the same silent downgrade the rest of this block prevents.
lookup="${TARGET#"${TARGET%%[![:space:]]*}"}"
lookup="${lookup%"${lookup##*[![:space:]]}"}"
lookup="${lookup##*@}"
lookup="${lookup#[}"
lookup="${lookup%%]*}"
case "$lookup" in
  *:*:*) : ;;
  *:*) lookup="${lookup%%:*}" ;;
esac
lookup="${lookup,,}"

canon="$lookup"
if [[ -n "${_SSH_KEY_FOR_HOST_BY_IP[$lookup]:-}" ]]; then
  canon="${_SSH_KEY_FOR_HOST_BY_IP[$lookup]}"
fi
if [[ -n "${_SSH_KEY_FOR_ALIAS[$canon]:-}" ]]; then
  canon="${_SSH_KEY_FOR_ALIAS[$canon]}"
fi
legacy="${_SSH_KEY_FOR_LEGACY[$canon]:-}"

# --- Which host is THIS resolver running on? ---------------------------------
# Only agent-06 has per-host keys as of phase 2a/2b (grotap_from06_*). Any
# other caller (the owner workstation, a future box) has no from-<N> keys to
# look for, so it falls straight through to the shared-key fallback.
_local_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
from_suffix=""
case "$_local_host" in
  agent-06|*agent-06*) from_suffix="06" ;;
esac

# Prints the path and exits the script when the file exists.
_ssh_key_for_use() {
  local path="$1"
  if [[ -n "$path" && -f "$path" ]]; then
    printf '%s\n' "$path"
    exit 0
  fi
}

if [[ -n "$from_suffix" ]]; then
  _ssh_key_for_use "$HOME/.ssh/grotap_from${from_suffix}_${canon}"
  if [[ -n "$legacy" ]]; then
    _ssh_key_for_use "$HOME/.ssh/grotap_from${from_suffix}_${legacy}"
  fi
  if [[ "$canon" == "prompt-01-claude" ]]; then
    _ssh_key_for_use "$HOME/.ssh/grotap_from${from_suffix}_claude-code-01"
  fi
fi

# --- 2. Workstation-style per-host key -------------------------------------
# The owner workstation names its per-host keys $HOME/.ssh/grotap_<host>
# (grotap_agent-04, grotap_forge-01, grotap_cobrowse-01, ...) rather than
# the grotap_from<N>_<host> form the fleet boxes use: there is only one
# source host, so the "from" half would carry no information. Without this
# branch the resolver handed back the SHARED key for every workstation call
# even though a per-host key was sitting right next to it -- exactly the
# dependency phase 2b exists to remove.
#
# A literal target of "agents" resolves to grotap_agents here, i.e. the
# shared key: the same answer the fallback gives, so it needs no guard.
_ssh_key_for_use "$HOME/.ssh/grotap_${canon}"
if [[ -n "$legacy" ]]; then
  _ssh_key_for_use "$HOME/.ssh/grotap_${legacy}"
fi
if [[ "$canon" == "prompt-01-claude" ]]; then
  _ssh_key_for_use "$HOME/.ssh/grotap_claude-code-01"
fi

printf '%s\n' "$SHARED_KEY"
exit 0

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
# agents/scripts/ssh-key-for.sh. Change one, copy to the other, then run
#   bash agents/scripts/ssh-key-for.twin-check.sh
# which diffs the two checkouts against EACH OTHER and fails on drift. A host
# missing from one copy does not raise: it falls through to the shared-key
# step below, and the caller's ssh then fails as an unreachable HOST rather
# than as a missing KEY.
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
#      <N> is derived from the CURRENT host's own short name (agent-06-claude
#      -> "06") and <canonical-target> is the Hetzner Cloud name
#      (agent-01-claude, and so on). Desktop keys are grotap_<hetzner-name>.
#      Files minted under the old slot stem (grotap_from06_agent-04, grotap_agent-01)
#      are tried second. Those filenames do not expire with the alias map.
#      TODO: drop key_file_stems only after the files on the hosts are renamed.
#      Do not rename key files during the freeze.
#      Aliases and key_file_stems are read from agents/fleet-aliases.json by
#      python3. When that file is present, python3 must be on PATH. A missing
#      interpreter exits 1:
#        ssh-key-for: python3 is required to load fleet aliases and key_file_stems
#      The message names the JSON path. Nothing is printed on stdout.
#      There is no offset. For a host key, $HOME reflects whichever OS user
#      actually runs this — /root under a root crontab, /home/agent under
#      `sudo -u agent` — so root and agent get the correct host key from the
#      exact same call, no extra flag. Phase 1 minted those host keys for
#      both source users.
#      A dedicated seat user (<user>@<host>, not root@ or agent@) does not
#      use $HOME. grotap-status.service runs dispatch as root, and each seat
#      authorizes only the one key under /home/agent/.ssh. Those keys resolve
#      from GROTAP_SEAT_KEY_DIR (default /home/agent/.ssh) for every uid.
#      A missing seat-key filename is skipped and the next name is tried. A
#      candidate that exists but is not a readable file fails closed.
#   2. Otherwise a workstation-style per-host key at
#      $HOME/.ssh/grotap_<canonical-target> -- the naming the owner
#      workstation uses. Fleet boxes have none of these and fall past it.
#   3. Otherwise, the shared fleet key: $HOME/.ssh/grotap_agents, but only
#      when that file exists and is readable. A missing or unreadable key
#      (including this fallback) exits 1 and names the path on stderr.
#      Nothing is printed on stdout. Callers must not substitute
#      grotap_agents when this script fails. Any target other than the
#      literal "agents" that reaches this step also gets a WARNING line on
#      stderr, so a key miss is not read as a dead host.
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
# Exit status: 0 when a readable key path is printed. A dedicated team user
# (<user>@<host>, not agent@ or root@) fails closed: exit 2 when the user
# is not ^[a-z_][a-z0-9_-]*$, exit 1 when no key file for that user exists
# in GROTAP_SEAT_KEY_DIR, and exit 1 when a candidate exists but is not a
# readable regular file (the next filename is not tried). Nothing is
# printed on those failures, and the shared fleet key is not a substitute.
# A host-key lookup prints a path only when that file exists and is
# readable. A missing or unreadable file, including the shared-key
# fallback and a per-host path that is not minted yet, exits 1 and names
# the path on stderr. Nothing is printed on stdout. A candidate that
# exists but is not a readable regular file fails closed; the next stem
# is not tried. A host-key lookup also exits 1 when fleet-aliases.json is
# present and python3 is missing or cannot read it. Exit 2 on a missing
# argument.
# fleet-aliases.json is loaded from the directory of this script's real
# path (readlink -f, then pwd -P), so a symlink such as
# /home/agent/scripts/ssh-key-for.sh still finds agents/fleet-aliases.json
# beside the file the link points at.
set -u

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "usage: ssh-key-for.sh <target-ip-or-host>" >&2
  exit 2
fi

SHARED_KEY="$HOME/.ssh/grotap_agents"

# The ops box (owner workstation) holds the grotap_from06_* keys. It was
# renamed agent-06 -> ops-01 on 2026-10-02; both names match. Team boxes
# (team-claude-01, team-codex-grok-monitor-01, team-astra-01) do not.
# GROTAP_OPS_HOST=1|0 forces the answer.
_ssh_key_for_is_ops_host() {
  case "${GROTAP_OPS_HOST:-}" in
    1|true|yes) return 0 ;;
    0|false|no) return 1 ;;
  esac
  case "$1" in
    agent-06-claude|agent-06|*agent-06*|ops-01|ops-01.*) return 0 ;;
  esac
  return 1
}

# --- IP -> Hetzner Cloud name (see header comment) --------------------------
# The key stem is the Hetzner Cloud name. Old slot names (agent-01, agent-20,
# cobrowse-01, runner-01, agent-06-ash) are NOT in this table. They resolve
# through agents/fleet-aliases.json until 2026-10-03. Do not map agent-01-claude
# onto a grotap_agent-02 file. Every TEAM_POOL host has a row. Astra and Team
# Grok do not fall through to the shared farm key.
# agent-21 / agent-31 / agent-41 were deleted 2026-09-16. agent-30
# (167.233.59.142) and llm-gpu-02 (178.63.124.99) were deleted 2026-09-20.
# Deleted 2026-09-26 and not mapped (Hetzner recycles the addresses):
#   agent-05-claude 5.78.178.81
#   prompt-01-claude / claude-code-01 / claudecode-01 178.156.209.112
#   agent-12-codex 178.156.203.132
# The name agent-14-monitor was deleted the same day. 178.156.215.173 is
# now agent-22-shared (Hetzner id 167604967) and is mapped below.
# forge-01 (178.156.246.81) stays on this row.
declare -A _SSH_KEY_FOR_HOST_BY_IP=(
  # 5.161.74.39 was agent-01-claude. That box was deleted and Hetzner recycled
  # the address to openreplay-02 (id 168488339) on 2026-10-02. The
  # agent-01-claude name row stays.
  ["5.161.74.39"]="openreplay-02"
  ["5.161.81.193"]="agent-02-claude"
  ["178.156.222.220"]="agent-03-claude"
  ["5.161.73.195"]="agent-04-claude"
  ["5.161.53.103"]="agent-06-claude"
  ["agent-01-claude"]="agent-01-claude"
  ["agent-02-claude"]="agent-02-claude"
  ["agent-03-claude"]="agent-03-claude"
  ["agent-04-claude"]="agent-04-claude"
  ["agent-06-claude"]="agent-06-claude"
  ["87.99.148.22"]="agent-10-codex"
  ["178.156.219.232"]="monitor-01-deepseek"
  ["5.161.243.18"]="prompt-01-astra"
  ["prompt-01-astra"]="prompt-01-astra"
  ["5.161.80.75"]="agent-team-01-astra"
  ["agent-team-01-astra"]="agent-team-01-astra"
  # Shared host. The team5 astra seat dials as the astra user. A bare
  # name or IP must not fall through to the shared farm key.
  ["5.161.119.92"]="agent-21-shared"
  ["agent-21-shared"]="agent-21-shared"
  # Shared host for codex, grok, and monitor. A bare name or IP must not
  # fall through to the shared farm key. Seats dial as their own users.
  ["178.156.215.173"]="agent-22-shared"
  ["agent-22-shared"]="agent-22-shared"
  # Team Grok. Cloud name = Linux hostname = SSH alias = key stem. No offset.
  # agent-06 file: $HOME/.ssh/grotap_from06_<name>. Not the shared farm key.
  # Display names are AgentGrok01 and AgentGrok02. agent-30 stays unmapped.
  ["5.161.83.78"]="agent-01-grok"
  ["agent-01-grok"]="agent-01-grok"
  ["5.161.82.78"]="agent-02-grok"
  ["agent-02-grok"]="agent-02-grok"
  ["agent-10-codex"]="agent-10-codex"
  ["monitor-01-deepseek"]="monitor-01-deepseek"
  # Live boxes that were missing from this table, so a name lookup fell
  # through to grotap_agents. The key stem is the host name. Both IPs
  # checked against the Hetzner API 2026-09-27 (farm project).
  ["178.156.222.217"]="agent-11-codex"
  ["agent-11-codex"]="agent-11-codex"
  ["178.156.212.74"]="agent-13-monitor"
  ["agent-13-monitor"]="agent-13-monitor"
  # agent-21/31/41 REMOVED 2026-09-16, agent-30 (167.233.59.142) and
  # llm-gpu-02 (178.63.124.99) REMOVED 2026-09-20: those Hetzner servers were
  # deleted or cancelled and their IPs released. Hetzner recycles released IPs,
  # so mapping one to a fleet host name would offer a fleet key to a stranger.
  # agent-05-claude (5.78.178.81) and prompt-01-claude (178.156.209.112)
  # were deleted 2026-09-26. Hetzner recycles released addresses, so do not
  # put those two back in this map. forge-01 was restored the same day.
  ["5.161.107.80"]="maps-01"
  # forge-01's address (restored in #175) and its name. Both stay. A
  # missing per-host key falls through to the shared fleet key — see the
  # header: maps-01/forge-01/GEX131 keep working off grotap_agents until
  # a per-host pair exists. No grotap_forge-01 key is deployed.
  ["178.156.246.81"]="forge-01"
  ["forge-01"]="forge-01"
  # Server renames 2026-10-02 (IPs and the old names are kept). The new
  # names resolve to the SAME key stem, because the key files on the ops box
  # keep their old names (grotap_from06_agent-21-shared, ...). Do not
  # rename key files during the freeze.
  ["team-claude-01"]="agent-21-shared"
  ["team-codex-grok-monitor-01"]="agent-22-shared"
  ["team-astra-01"]="agent-team-01-astra"
  ["ops-01"]="agent-06-claude"
  ["openreplay-ai-support-01"]="openreplay-ai-support"
  # openreplay-02 (ccx23, 5.161.74.39) took over supportagents.grotap.com on
  # 2026-10-02. It carries the authorized_keys of the old OpenReplay box, so
  # key_file_stems maps it to the existing cobrowse-01 key files.
  # openreplay-01 (5.161.189.143) was deleted 2026-10-03 00:26 PT. Its name
  # and IP are not mapped (Hetzner recycles released addresses).
  ["supportagents.grotap.com"]="openreplay-02"
  ["openreplay-02"]="openreplay-02"
  ["178.156.199.83"]="openreplay-ai-support"
  ["openreplay-ai-support"]="openreplay-ai-support"
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
# Capture a dedicated team user before the host-key path strips user@.
# agent@ and root@ stay on that path (single-team boxes).
_team_user_raw=""
if [[ "$lookup" == *@* ]]; then
  _team_user_raw="${lookup%%@*}"
fi
lookup="${lookup##*@}"
lookup="${lookup#[}"
lookup="${lookup%%]*}"
case "$lookup" in
  *:*:*) : ;;
  *:*) lookup="${lookup%%:*}" ;;
esac
lookup="${lookup,,}"
_team_user_raw="${_team_user_raw,,}"

# Dedicated team user on a shared host: <user>@<host>. agent@ and root@ are
# the historical single-team destinations and keep the host-key path below.
# A team user's key is only that user's file, in one directory, for every
# caller uid. Never $HOME, never the shared fleet key, and never a file
# named for a different user. An empty GROTAP_SEAT_KEY_DIR uses the default.
team_user="$_team_user_raw"
if [[ -n "$team_user" && "$team_user" != "root" && "$team_user" != "agent" ]]; then
  # claude@ with no host is not a seat. A present key file must not exit 0.
  if [[ -z "$lookup" ]]; then
    echo "ssh-key-for: refusing empty host" >&2
    exit 2
  fi
  # Fail closed. A user of "../" or "claude;rm" must not become a path,
  # and a missing file must not exit 0 (ssh would then try other identities).
  if [[ ! "$team_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "ssh-key-for: refusing user name" >&2
    exit 2
  fi
  _SEAT_KEY_DIR="${GROTAP_SEAT_KEY_DIR:-/home/agent/.ssh}"
  _seat_try() {
    local cand="$1"
    if [[ -e "$cand" ]]; then
      if [[ ! -f "$cand" || ! -r "$cand" ]]; then
        echo "ssh-key-for: key file is not readable: ${cand}" >&2
        exit 1
      fi
      printf '%s\n' "$cand"
      exit 0
    fi
  }
  _local_for_team="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  _team_from=""
  if _ssh_key_for_is_ops_host "$_local_for_team"; then
    _team_from="06"
  fi
  if [[ -n "$_team_from" ]]; then
    _seat_try "$_SEAT_KEY_DIR/grotap_from${_team_from}_${team_user}"
  fi
  _seat_try "$_SEAT_KEY_DIR/${team_user}_ed25519"
  _seat_try "$_SEAT_KEY_DIR/grotap_${team_user}"
  echo "ssh-key-for: no key file for user ${team_user} in ${_SEAT_KEY_DIR}" >&2
  exit 1
fi

# TODO(2026-10-03): delete the alias load. Old slot names are not key stems.
# key_file_stems is separate and does not expire: the files on disk keep the
# pre-rename names (grotap_from06_agent-04, and so on) until they are renamed.
# python3 is required to read this JSON. A missing interpreter exits 1
# before any key path is printed, so key_file_stems either load or the
# call fails.
# Resolve this file, not the symlink that invoked it. Root cron on
# agent-06 runs /home/agent/scripts/ssh-key-for.sh, which is a link to
# this copy. dirname of the link looks for fleet-aliases.json under
# /home/agent, where it is not installed, and then the key stem stays
# agent-0N-claude instead of the on-disk grotap_from06_agent-0N.
_ssh_key_for_src="${BASH_SOURCE[0]}"
_ssh_key_for_real=""
if command -v readlink >/dev/null 2>&1; then
  _ssh_key_for_real="$(readlink -f -- "$_ssh_key_for_src" 2>/dev/null || true)"
fi
if [[ -z "$_ssh_key_for_real" ]]; then
  _ssh_key_for_real="$_ssh_key_for_src"
  while [[ -L "$_ssh_key_for_real" ]]; do
    _ssh_key_for_dir="$(cd "$(dirname "$_ssh_key_for_real")" && pwd -P)"
    _ssh_key_for_target="$(readlink "$_ssh_key_for_real")"
    if [[ "$_ssh_key_for_target" != /* ]]; then
      _ssh_key_for_real="$_ssh_key_for_dir/$_ssh_key_for_target"
    else
      _ssh_key_for_real="$_ssh_key_for_target"
    fi
  done
fi
_ssh_key_for_dir="$(cd "$(dirname "$_ssh_key_for_real")" && pwd -P)"
_FLEET_ALIAS_JSON="$(cd "$_ssh_key_for_dir/.." && pwd -P)/fleet-aliases.json"
declare -A _FLEET_ALIASES=()
declare -A _SSH_KEY_LEGACY_STEMS=()
if [[ -n "${FLEET_ALIAS_TODAY:-}" ]]; then
  _fleet_alias_today="$FLEET_ALIAS_TODAY"
else
  _fleet_alias_today="$(TZ=America/Los_Angeles date +%Y-%m-%d)"
fi
if [[ -f "$_FLEET_ALIAS_JSON" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ssh-key-for: python3 is required to load fleet aliases and key_file_stems from ${_FLEET_ALIAS_JSON}" >&2
    exit 1
  fi
  _alias_rows="$(python3 -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
today = sys.argv[2]
deadline = str(doc.get("remove_after") or "")
if deadline and today > deadline:
    print(f"fleet aliases expired on {deadline}; ignoring alias map", file=sys.stderr)
else:
    for old, new in (doc.get("aliases") or {}).items():
        print(f"alias\t{old}\t{new}")
stems = doc.get("key_file_stems") or doc.get("legacy_key_stems") or {}
for canon, names in stems.items():
    for stem in names:
        print(f"stem\t{canon}\t{stem}")
' "$_FLEET_ALIAS_JSON" "$_fleet_alias_today")" || {
    echo "ssh-key-for: python3 failed to read fleet aliases and key_file_stems from ${_FLEET_ALIAS_JSON}" >&2
    exit 1
  }
  while IFS=$'\t' read -r _kind _old _new; do
    [[ -z "${_old:-}" || -z "${_new:-}" ]] && continue
    case "$_kind" in
      alias) _FLEET_ALIASES["$_old"]="$_new" ;;
      stem)
        if [[ -n "${_SSH_KEY_LEGACY_STEMS[$_old]:-}" ]]; then
          _SSH_KEY_LEGACY_STEMS["$_old"]+=" $_new"
        else
          _SSH_KEY_LEGACY_STEMS["$_old"]="$_new"
        fi
        ;;
    esac
  done <<< "$_alias_rows"
fi
if [[ -n "${_FLEET_ALIASES[$lookup]:-}" ]]; then
  lookup="${_FLEET_ALIASES[$lookup]}"
fi

canon="$lookup"
if [[ -n "${_SSH_KEY_FOR_HOST_BY_IP[$lookup]:-}" ]]; then
  canon="${_SSH_KEY_FOR_HOST_BY_IP[$lookup]}"
fi

# --- Which host is THIS resolver running on? ---------------------------------
# Only agent-06 has per-host keys as of phase 2a/2b (grotap_from06_*). Any
# other caller (the owner workstation, a future box) has no from-<N> keys to
# look for, so it falls straight through to the shared-key fallback.
_local_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
from_suffix=""
if _ssh_key_for_is_ops_host "$_local_host"; then
  from_suffix="06"
fi

# Stems to try: the canonical name, then any pre-rename filename.
_key_stems=("$canon")
if [[ -n "${_SSH_KEY_LEGACY_STEMS[$canon]:-}" ]]; then
  # shellcheck disable=SC2206
  _key_stems+=(${_SSH_KEY_LEGACY_STEMS[$canon]})
fi

# A present file that is not a readable regular file fails closed. A
# missing file returns so the next stem can be tried. The path that would
# be printed (including the shared key) is checked the same way: missing
# or unreadable exits 1 and prints nothing on stdout.
_try_key_file() {
  local cand="$1"
  if [[ ! -e "$cand" ]]; then
    return 1
  fi
  if [[ -f "$cand" && -r "$cand" ]]; then
    printf '%s\n' "$cand"
    exit 0
  fi
  echo "ssh-key-for: key file is not readable: ${cand}" >&2
  exit 1
}
_require_key_file() {
  local cand="$1"
  if [[ -f "$cand" && -r "$cand" ]]; then
    printf '%s\n' "$cand"
    exit 0
  fi
  if [[ -e "$cand" ]]; then
    echo "ssh-key-for: key file is not readable: ${cand}" >&2
  else
    echo "ssh-key-for: key file does not exist: ${cand}" >&2
  fi
  exit 1
}

if [[ -n "$from_suffix" ]]; then
  for _stem in "${_key_stems[@]}"; do
    _try_key_file "$HOME/.ssh/grotap_from${from_suffix}_${_stem}" || true
  done
fi

# --- 2. Workstation-style per-host key -------------------------------------
# The owner workstation names its per-host keys $HOME/.ssh/grotap_<host>
# (grotap_agent-04, grotap_forge-01, grotap_cobrowse-01, ...) rather than
# the grotap_from<N>_<host> form the fleet boxes use: there is only one
# source host, so the "from" half would carry no information. Without this
# branch the resolver handed back the SHARED key for every workstation call
# even though a per-host key was sitting right next to it -- exactly the
# dependency phase 2b exists to remove. A renamed host tries the new stem
# first, then the file that was minted under the old name.
#
# A literal target of "agents" resolves to grotap_agents here, i.e. the
# shared key: the same answer the fallback gives, so it needs no guard.
for _stem in "${_key_stems[@]}"; do
  _try_key_file "$HOME/.ssh/grotap_${_stem}" || true
done

# Astra is per-host only. A missing file must not offer the shared farm key.
# forge-01 and agent-06 have no own key deployed (no grotap_forge-01,
# no grotap_from06_agent-06). They stay off this list and fall through
# to grotap_agents, matching the header note on maps-01/forge-01/GEX131.
case "$canon" in
  prompt-01-astra|agent-team-01-astra|agent-21-shared|agent-22-shared|agent-01-grok|agent-02-grok|agent-11-codex|agent-13-monitor)
    if [[ -n "$from_suffix" ]]; then
      _require_key_file "$HOME/.ssh/grotap_from${from_suffix}_${canon}"
    else
      _require_key_file "$HOME/.ssh/grotap_${canon}"
    fi
    ;;
esac

# --- 3. Shared-key fallthrough ----------------------------------------------
# Reaching here means no per-host key was found. The shared fleet key is
# being retired, so this answer increasingly means "a key the host does not
# accept", and the caller's ssh then fails as an unreachable HOST, not a
# missing KEY. Say so on stderr. stdout and the exit code are unchanged.
# The literal target "agents" IS the shared key by name, not a fallthrough.
if [[ "$canon" != "agents" ]]; then
  printf 'ssh-key-for: WARNING: no per-host key for %s -- falling back to the RETIRED shared key %s. If ssh now fails, the host is probably reachable and the KEY is the problem: register a per-host key (see agents/SERVERS.md).\n' \
    "$canon" "$SHARED_KEY" >&2
fi
_require_key_file "$SHARED_KEY"

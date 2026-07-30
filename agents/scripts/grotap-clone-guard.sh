#!/bin/bash
# grotap-clone-guard — keep the fleet's shared clones owned by `agent`.
#
# CASE-20260730-9B4988.
#
# THE SECOND, DIFFERENT FAILURE. `cannot lock ref` is a race (see
# grotap-git-lock). This is not that, and conflating the two is why the review
# gate's merge path has been "fixed" twice without getting better:
#
#   race        error: cannot lock ref 'refs/remotes/origin/master': is at X but expected Y
#               -> intermittent, a different SHA every time, clears on the next tick.
#                  A retry loop genuinely helps.
#
#   ownership   error: unable to unlink old '<path>': Permission denied
#               error: unable to create file '<path>': Permission denied
#               fatal: Could not reset index file to revision 'origin/master'
#               -> DETERMINISTIC. Same path every time, every retry, for hours.
#                  Seen 2026-07-09 12:30 through 15:30 (7 consecutive runs, both
#                  retries each), 2026-07-13 04:00 and 04:30, and again
#                  2026-07-30 00:02 and 00:32. A retry loop can NEVER win it.
#
# The cause is root writing into an agent-owned clone. Both of these do it:
#   - root cron jobs that `cd /home/agent/grotap-platform` and run as root
#     (expense ingest, publish-release-notes, agb-launch-check, semimonthly
#     source backup) — chiefly via root-owned __pycache__ directories;
#   - root SSH sessions. The 2026-07-30 00:02 failure was preceded by a burst
#     of root logins from 98.97.42.55 at 23:53-23:55 doing incident work in
#     that very tree; by 01:00 the strays had been cleaned up by hand, which is
#     exactly why the ownership theory keeps getting dismissed as "a race" when
#     someone checks after the fact and finds everything agent-owned.
#
# This guard does not replace fixing the writers. It bounds the blast radius to
# one interval and — more importantly — makes the event VISIBLE and dated in a
# log, instead of a merge path that silently stops for hours.
set -uo pipefail

LOG=${CLONE_GUARD_LOG:-/var/log/grotap-clone-guard.log}
REPOS=${CLONE_GUARD_REPOS:-"/home/agent/grotap-platform /home/agent/grotap-agents"}
ts() { date -u +%FT%TZ; }

rc=0
for repo in $REPOS; do
  [ -d "$repo" ] || continue

  # node_modules is excluded from DETECTION only (it is huge and npm churns it);
  # the chown below still repairs it, so a stray there cannot linger.
  strays="$(find "$repo" -not -user agent -not -path '*/node_modules/*' -printf '%u:%g %p\n' 2>/dev/null)"
  [ -n "$strays" ] || continue

  n=$(printf '%s\n' "$strays" | grep -c . || true)
  {
    printf '%s [clone-guard] %s: %s non-agent path(s) found — repairing to agent:agent\n' "$(ts)" "$repo" "$n"
    printf '%s\n' "$strays" | head -50
    [ "$n" -gt 50 ] && printf '  ... and %s more\n' "$((n - 50))"
  } >>"$LOG"

  if chown -R agent:agent "$repo" 2>>"$LOG"; then
    printf '%s [clone-guard] %s: repaired\n' "$(ts)" "$repo" >>"$LOG"
  else
    printf '%s [clone-guard] %s: CHOWN FAILED\n' "$(ts)" "$repo" >>"$LOG"
    rc=1
  fi
done

exit $rc

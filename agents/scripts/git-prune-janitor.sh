#!/usr/bin/env bash
# Git prune janitor — CASE-20260725-0374AD (GATEBOOT), D2.
#
# review-gate-cron.sh deliberately does NOT run `git fetch --prune` on its
# bootstrap hot path: pruning races the fleet/orchestrator recreating case-*
# branches, and that race filed intermittent "could not sync grotap-platform"
# holds that paged a human and skipped a whole gate cycle.
#
# Pruning still has to happen sometime, so it happens here — on its own
# schedule, where a failure costs nothing and can never block a gate run.
#
# Installed on agent-06:
#   17 4 * * *  /home/agent/grotap-agents/agents/scripts/git-prune-janitor.sh >> /home/agent/logs/git-prune-janitor.log 2>&1
#
# Manual run: bash /home/agent/grotap-agents/agents/scripts/git-prune-janitor.sh
set -uo pipefail

AGENT_HOME="/home/agent"
echo "=== git-prune-janitor run $(date -u +%FT%TZ) ==="

for repo in "$AGENT_HOME/grotap-agents" "$AGENT_HOME/grotap-platform"; do
  if [ ! -d "$repo/.git" ]; then
    echo "skip $repo (not a git checkout)"
    continue
  fi
  # Never fail the job: this is opportunistic tidy-up, not a gate.
  if (cd "$repo" && git fetch origin --prune 2>&1); then
    echo "pruned $repo"
  else
    echo "prune failed for $repo (ignored — next run retries)"
  fi
done

echo "=== git-prune-janitor done $(date -u +%FT%TZ) ==="
exit 0

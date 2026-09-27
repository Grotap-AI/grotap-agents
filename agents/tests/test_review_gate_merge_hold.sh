#!/bin/bash
# agents/tests/test_review_gate_merge_hold.sh
#
# The review gate must not claim or merge a case that still has a pending
# Approve-merge hold, and it must not run on any host but agent-06-claude.
#
#   H1  host guard: agent-01-claude (and the SSH alias agent-06) exits 1
#       before the run log, the lock, or any git/DB work
#   H2  host guard: hostname -s agent-06-claude is allowed
#   H3  the call sits above the log redirect and the lock
#   L1  the hold WHERE in review-gate-cron.sh and review-gate-task.md §0
#       is the same text on both UNION arms, and §3's backstop WHERE matches
#       the aliased arm. A one-sided edit fails this.
#   L2  claim/pre-check wrap that WHERE in NOT EXISTS; §3 wraps it in EXISTS
#   L3  sqlite runs the extracted WHERE: a held case is absent from the queue
#       and present in the backstop; an unheld case is in the queue and absent
#       from the backstop
#
# No SSH, no Doppler, no fleet host. Usage:
#   bash agents/tests/test_review_gate_merge_hold.sh [--verbose]

set -uo pipefail
VERBOSE=0; [[ "${1:-}" == "--verbose" ]] && VERBOSE=1

PASS=0; FAIL=0
TMP=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRON="$SCRIPT_DIR/../scripts/review-gate-cron.sh"
TASK="$SCRIPT_DIR/../scripts/review-gate-task.md"
trap 'rm -rf "$TMP"' EXIT

vlog() { [[ $VERBOSE -eq 1 ]] && printf '  [dbg] %s\n' "$*" || true; }
check() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "true" ]]; then PASS=$((PASS+1)); printf 'PASS: %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$desc"; fi
}

bash -n "$CRON" || { echo "FATAL: review-gate-cron.sh does not parse"; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || { echo "FATAL: sqlite3 is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 is required"; exit 1; }

# ─── H1/H2/H3 host guard ────────────────────────────────────────────────────
cat > "$TMP/hostname" << 'EOF'
#!/bin/bash
# Test double. The first argument, when present, is ignored: both `hostname`
# and `hostname -s` print the name in HOSTNAME_MOCK.
printf '%s\n' "${HOSTNAME_MOCK:?HOSTNAME_MOCK unset}"
EOF
chmod +x "$TMP/hostname"

run_guard() {
  local name="$1"
  HOSTNAME_MOCK="$name" PATH="$TMP:$PATH" bash "$CRON" >"$TMP/out" 2>"$TMP/err"
  return $?
}

run_guard "agent-01-claude"
rc=$?
check "H1 agent-01-claude exits 1" "$([[ $rc -eq 1 ]] && echo true || echo false)"
check "H1 names the refused host" "$(grep -q "refuses to run on host 'agent-01-claude'" "$TMP/err" && echo true || echo false)"
check "H1 does not start a review run" "$(grep -q 'review-gate run' "$TMP/out" "$TMP/err" && echo false || echo true)"
check "H1 does not take the lock" "$([[ -e /home/agent/.review-gate.lock ]] && echo false || echo true)"

run_guard "agent-06"
rc=$?
check "H1 SSH alias agent-06 exits 1" "$([[ $rc -eq 1 ]] && echo true || echo false)"
check "H1 alias does not start a review run" "$(grep -q 'review-gate run' "$TMP/out" && echo false || echo true)"

# The function is what the script calls. Source only that function so the
# allow-path does not sync repos or write /home/agent.
awk '/^review_gate_assert_canonical_host\(\)/,/^}/' "$CRON" > "$TMP/guard.sh"
# shellcheck disable=SC1091
HOSTNAME_MOCK="agent-06-claude" PATH="$TMP:$PATH" bash -c 'source "$1"; review_gate_assert_canonical_host' _ "$TMP/guard.sh"
rc=$?
check "H2 agent-06-claude is the canonical host" "$([[ $rc -eq 0 ]] && echo true || echo false)"

HOSTNAME_MOCK="agent-01-claude" PATH="$TMP:$PATH" bash -c 'source "$1"; review_gate_assert_canonical_host' _ "$TMP/guard.sh" >/dev/null 2>&1
rc=$?
check "H2 sourced guard still refuses agent-01-claude" "$([[ $rc -eq 1 ]] && echo true || echo false)"

guard_order=$(python3 - "$CRON" << 'PY'
import sys
text = open(sys.argv[1]).read().splitlines()
call = next(i for i, line in enumerate(text) if "review_gate_assert_canonical_host || exit 1" in line)
mkdir = next(i for i, line in enumerate(text) if line.startswith("mkdir -p "))
redirect = next(i for i, line in enumerate(text) if 'exec >>"$LOG"' in line)
lock = next(i for i, line in enumerate(text) if '> "$LOCK"' in line)
print("true" if call < mkdir and call < redirect and call < lock else "false")
PY
)
check "H3 guard runs before mkdir, log redirect, and lock" "$guard_order"

# ─── L1/L2 lockstep of the hold predicate ───────────────────────────────────
python3 - "$CRON" "$TASK" "$TMP/where_case" "$TMP/where_alias" "$TMP/where_backstop" > "$TMP/lockstep" << 'PY'
import re, sys
cron_path, task_path, out_case, out_alias, out_back = sys.argv[1:6]
cron = open(cron_path, encoding="utf-8").read()
task = open(task_path, encoding="utf-8").read()
pat = re.compile(
    r"/\*RG_MERGE_HOLD_WHERE ([^*]+)\*/(.*?)/\*RG_MERGE_HOLD_WHERE_END\*/",
    re.S,
)

def norm(s):
    return re.sub(r"\s+", " ", s).strip()

def blocks(text):
    out = []
    for m in pat.finditer(text):
        key = m.group(1).strip()
        body = norm(m.group(2))
        window = text[max(0, m.start() - 180):m.start()]
        kinds = re.findall(r"NOT EXISTS|EXISTS", window)
        kind = kinds[-1] if kinds else ""
        out.append((key, body, kind, m.start()))
    return out

cron_blocks = blocks(cron)
sec3 = task.find("## 3. Merge")
sec4 = task.find("## 4. Aftercare")
task_blocks = blocks(task)
claim = [b for b in task_blocks if b[3] < sec3]
backstop = [b for b in task_blocks if sec3 < b[3] < sec4]
elsewhere = [b for b in task_blocks if b not in claim and b not in backstop]

def by_key(rows):
    d = {}
    for key, body, kind, _pos in rows:
        d.setdefault(key, []).append((body, kind))
    return d

fails = []
if elsewhere:
    fails.append(f"hold marker outside §0 and §3: {len(elsewhere)}")
ck, tk = by_key(cron_blocks), by_key(claim)
if set(ck) != {"case_id", "c.case_id"}:
    fails.append(f"cron keys {sorted(ck)}")
if set(tk) != {"case_id", "c.case_id"}:
    fails.append(f"claim keys {sorted(tk)}")
for key in ("case_id", "c.case_id"):
    if key not in ck or key not in tk:
        continue
    if len(ck[key]) != 1 or len(tk[key]) != 1:
        fails.append(f"{key} count cron={len(ck[key])} claim={len(tk[key])}")
        continue
    if ck[key][0][0] != tk[key][0][0]:
        fails.append(f"{key} WHERE diverged\n  cron: {ck[key][0][0]}\n  task: {tk[key][0][0]}")
    if ck[key][0][1] != "NOT EXISTS" or tk[key][0][1] != "NOT EXISTS":
        fails.append(f"{key} wrapper cron={ck[key][0][1]} claim={tk[key][0][1]}")
if len(backstop) != 1 or backstop[0][0] != "c.case_id":
    fails.append(f"backstop markers {[b[0] for b in backstop]}")
elif "c.case_id" in ck and backstop[0][1] != ck["c.case_id"][0][0]:
    fails.append("backstop WHERE diverged from cron c.case_id arm")
elif backstop and backstop[0][2] != "EXISTS":
    fails.append(f"backstop wrapper {backstop[0][2]}")

body = ck.get("case_id", [("", "")])[0][0]
for literal in (
    "h.status = 'pending'",
    "h.created_by = 'agent-progress'",
    "h.category = 'approval'",
    "h.task_title = 'Approve merge'",
    "h.task_title LIKE 'Approve merge %'",
    "h.description LIKE 'Approve merge of %'",
    "h.description LIKE 'Awaiting human approval — branch %'",
    "h.task_id = case_id",
):
    if literal not in body:
        fails.append(f"missing literal {literal}")
aliased = ck.get("c.case_id", [("", "")])[0][0]
if "h.task_id = c.case_id" not in aliased:
    fails.append("aliased arm does not bind h.task_id = c.case_id")

sec3_text = task[sec3:sec4]
for phrase in ("do not merge", "do not set status to done", "leave the status unchanged"):
    if phrase not in sec3_text:
        fails.append(f"§3 missing phrase: {phrase}")

if "status='change_review'" not in cron or "awaiting_review" not in cron:
    fails.append("cron lost the unheld queue shape")
if "INTERVAL '${CLAIM_TTL_MINUTES} minutes'" not in cron:
    fails.append("cron lost CLAIM_TTL_MINUTES predicate")
if "status = 'change_review'" not in task or "INTERVAL '30 minutes'" not in task:
    fails.append("claim lost the unheld queue shape")
if "LIMIT 15" not in task:
    fails.append("claim lost LIMIT 15")

# A one-sided edit must fail this comparison. Mutate a copy of the task and
# re-run the same extractor; if the cron still matches, the lockstep check is blind.
mutated = task.replace("h.created_by = 'agent-progress'", "h.created_by = 'not-the-webhook'", 1)
mut_claim = [b for b in blocks(mutated) if b[3] < mutated.find("## 3. Merge")]
mut_by = {}
for key, body, kind, _pos in mut_claim:
    mut_by.setdefault(key, body)
if mut_by.get("case_id") == ck.get("case_id", [("", "")])[0][0]:
    fails.append("lockstep did not notice a one-sided edit of the claim WHERE")

if fails:
    print("FAIL")
    print("\n".join(fails))
    sys.exit(0)
print("OK")
open(out_case, "w", encoding="utf-8").write(ck["case_id"][0][0] + "\n")
open(out_alias, "w", encoding="utf-8").write(ck["c.case_id"][0][0] + "\n")
open(out_back, "w", encoding="utf-8").write(backstop[0][1] + "\n")
PY
lock_status=$(head -1 "$TMP/lockstep")
check "L1/L2 hold predicates stay in lockstep" "$([[ "$lock_status" == "OK" ]] && echo true || echo false)"
if [[ "$lock_status" != "OK" ]]; then
  echo "---- lockstep detail ----"
  cat "$TMP/lockstep"
fi

# ─── L3 held cases are not queued and are skipped at merge ──────────────────
if [[ "$lock_status" == "OK" ]]; then
  WHERE_CASE=$(cat "$TMP/where_case")
  WHERE_ALIAS=$(cat "$TMP/where_alias")
  WHERE_BACK=$(cat "$TMP/where_backstop")
  sqlite3 "$TMP/gate.db" << SQL
CREATE TABLE pipeline_cases (case_id TEXT, status TEXT, claimed_by TEXT, claimed_at TEXT);
CREATE TABLE human_holds (
  task_id TEXT, status TEXT, created_by TEXT, category TEXT,
  task_title TEXT, description TEXT
);
CREATE TABLE pipeline_dispatch_log (case_id TEXT, status TEXT);

INSERT INTO pipeline_cases (case_id, status) VALUES
  ('UNHELD_CR', 'change_review'),
  ('HELD_EXACT', 'change_review'),
  ('HELD_TITLE_OF', 'change_review'),
  ('HELD_DESC', 'change_review'),
  ('HELD_BRANCH', 'change_review'),
  ('CLARIFICATION', 'change_review'),
  ('RESOLVED', 'change_review'),
  ('OTHER_AUTHOR', 'change_review'),
  ('OTHER_CATEGORY', 'change_review'),
  ('UNHELD_PARKED', 'awaiting_human'),
  ('HELD_PARKED', 'awaiting_human'),
  ('NOT_PARKED', 'awaiting_human'),
  ('DONE_HELD', 'done');

INSERT INTO pipeline_dispatch_log (case_id, status) VALUES
  ('UNHELD_PARKED', 'awaiting_review'),
  ('HELD_PARKED', 'awaiting_review');

INSERT INTO human_holds (task_id, status, created_by, category, task_title, description) VALUES
  ('HELD_EXACT', 'pending', 'agent-progress', 'approval', 'Approve merge', 'waiting'),
  ('HELD_TITLE_OF', 'pending', 'agent-progress', 'approval', 'Approve merge of origin/case-HELD_TITLE_OF', 'review'),
  ('HELD_DESC', 'pending', 'agent-progress', 'approval', 'CASE HELD_DESC', 'Approve merge of origin/case-HELD_DESC'),
  ('HELD_BRANCH', 'pending', 'agent-progress', 'approval', 'CASE HELD_BRANCH', 'Awaiting human approval — branch case-HELD_BRANCH'),
  ('HELD_PARKED', 'pending', 'agent-progress', 'approval', 'Approve merge', 'waiting'),
  ('CLARIFICATION', 'pending', 'agent-progress', 'clarification', 'Question', 'what color?'),
  ('RESOLVED', 'resolved', 'agent-progress', 'approval', 'Approve merge', 'waiting'),
  ('OTHER_AUTHOR', 'pending', 'review-gate-cron', 'approval', 'Approve merge', 'waiting'),
  ('OTHER_CATEGORY', 'pending', 'agent-progress', 'manual_verification', 'Approve merge', 'waiting'),
  ('DONE_HELD', 'pending', 'agent-progress', 'approval', 'Approve merge', 'waiting');
SQL

  sqlite3 "$TMP/gate.db" << SQL > "$TMP/queue_ids"
SELECT case_id FROM pipeline_cases
WHERE status = 'change_review'
  AND (claimed_by IS NULL OR claimed_at IS NULL)
  AND NOT EXISTS (
    SELECT 1 FROM human_holds h
    WHERE $WHERE_CASE
  )
UNION
SELECT c.case_id FROM pipeline_cases c
WHERE c.status = 'awaiting_human'
  AND (c.claimed_by IS NULL OR c.claimed_at IS NULL)
  AND EXISTS (
    SELECT 1 FROM pipeline_dispatch_log dl
    WHERE dl.case_id = c.case_id AND dl.status = 'awaiting_review'
  )
  AND NOT EXISTS (
    SELECT 1 FROM human_holds h
    WHERE $WHERE_ALIAS
  )
ORDER BY 1;
SQL

  sqlite3 "$TMP/gate.db" << SQL > "$TMP/skip_ids"
SELECT c.case_id FROM pipeline_cases c
WHERE EXISTS (
  SELECT 1 FROM human_holds h
  WHERE $WHERE_BACK
)
ORDER BY 1;
SQL

  vlog "queue:"; vlog "$(cat "$TMP/queue_ids")"
  vlog "skip:"; vlog "$(cat "$TMP/skip_ids")"

  has() { grep -qx "$1" "$2"; }
  check "L3 unheld change_review is claimable" "$(has UNHELD_CR "$TMP/queue_ids" && echo true || echo false)"
  check "L3 clarification hold is still claimable" "$(has CLARIFICATION "$TMP/queue_ids" && echo true || echo false)"
  check "L3 resolved Approve-merge hold is claimable" "$(has RESOLVED "$TMP/queue_ids" && echo true || echo false)"
  check "L3 other author's Approve merge hold stays claimable" "$(has OTHER_AUTHOR "$TMP/queue_ids" && echo true || echo false)"
  check "L3 non-approval category stays claimable" "$(has OTHER_CATEGORY "$TMP/queue_ids" && echo true || echo false)"
  check "L3 unheld parked awaiting_review is claimable" "$(has UNHELD_PARKED "$TMP/queue_ids" && echo true || echo false)"
  check "L3 awaiting_human without awaiting_review stays out" "$(has NOT_PARKED "$TMP/queue_ids" && echo false || echo true)"
  check "L3 exact Approve merge hold is not claimed" "$(has HELD_EXACT "$TMP/queue_ids" && echo false || echo true)"
  check "L3 'Approve merge of …' title is not claimed" "$(has HELD_TITLE_OF "$TMP/queue_ids" && echo false || echo true)"
  check "L3 'Approve merge of …' description is not claimed" "$(has HELD_DESC "$TMP/queue_ids" && echo false || echo true)"
  check "L3 'Awaiting human approval — branch' is not claimed" "$(has HELD_BRANCH "$TMP/queue_ids" && echo false || echo true)"
  check "L3 parked case with Approve-merge hold is not claimed" "$(has HELD_PARKED "$TMP/queue_ids" && echo false || echo true)"
  check "L3 done case is not claimed" "$(has DONE_HELD "$TMP/queue_ids" && echo false || echo true)"
  check "L3 exact hold is a merge skip" "$(has HELD_EXACT "$TMP/skip_ids" && echo true || echo false)"
  check "L3 title-of hold is a merge skip" "$(has HELD_TITLE_OF "$TMP/skip_ids" && echo true || echo false)"
  check "L3 description hold is a merge skip" "$(has HELD_DESC "$TMP/skip_ids" && echo true || echo false)"
  check "L3 branch-approval hold is a merge skip" "$(has HELD_BRANCH "$TMP/skip_ids" && echo true || echo false)"
  check "L3 parked hold is a merge skip" "$(has HELD_PARKED "$TMP/skip_ids" && echo true || echo false)"
  check "L3 unheld case is not a merge skip" "$(has UNHELD_CR "$TMP/skip_ids" && echo false || echo true)"
  check "L3 unheld parked case is not a merge skip" "$(has UNHELD_PARKED "$TMP/skip_ids" && echo false || echo true)"
  overlap=$(comm -12 <(sort "$TMP/queue_ids") <(sort "$TMP/skip_ids") | tr '\n' ' ')
  check "L3 queue and merge-skip sets are disjoint" "$([[ -z "$overlap" ]] && echo true || echo false)"
else
  check "L3 sqlite evaluation skipped because lockstep failed" "false"
fi

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

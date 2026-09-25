#!/bin/bash
# drivers/run-claude.sh — Team Claude driver for orchestrator-run.sh.
#
# Model choice, the claude -p invocation, the JSON parse, and the tool-denial
# note are the historical wrapper block, moved here unchanged in behavior.
# ONE attempt. No retry ladder and no cross-model fallback — the graph owns
# retries. cache_read / cache_creation map onto cached_input / cache_write_input
# and those two are subsets of tokens.input (they are added to Claude's
# input_tokens, which does not already include them).
#
# Args: <worktree> <prompt-file> <driver-result-json>
# Human logs go to the shared runner log and to stderr (the wrapper appends
# stderr to the per-run log). The result file is schema driver-result/v1.
set -uo pipefail

WT="${1:?worktree required}"
PROMPT_FILE="${2:?prompt file required}"
OUT_JSON="${3:?driver-result path required}"
LOG="${LOG:-$HOME/logs/orchestrator-run.log}"

log() {
  local line="[$(date -u +%H:%M:%S)] $*"
  echo "$line" >> "$LOG"
  echo "$line" >&2
}

CLAUDE_OUT=""
DR_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ATTEMPTS_INSIDE=0
DR_STATUS="failed"
DR_ERRORS="error_class=infra claude driver failed before the model call"
DR_SUMMARY="Claude driver failed (infra, not a task defect)"
DR_ERROR_CLASS="infra"
MODEL=""
DRIVER_VERSION=""
TOOL_BIN=""
CLAUDE_RC=1

write_driver_result() {
  local ended raw
  ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  raw="$(mktemp)"
  printf '%s' "$CLAUDE_OUT" > "$raw"
  DR_STATUS="$DR_STATUS" DR_ERRORS="$DR_ERRORS" DR_SUMMARY="$DR_SUMMARY" \
  DR_ERROR_CLASS="${DR_ERROR_CLASS:-}" \
  DR_STARTED_AT="$DR_STARTED_AT" DR_ENDED_AT="$ended" \
  MODEL="${MODEL:-}" DRIVER_VERSION="${DRIVER_VERSION:-}" TOOL_BIN="${TOOL_BIN:-}" \
  ORCH_TEAM="${ORCH_TEAM:-team1}" ATTEMPTS_INSIDE="$ATTEMPTS_INSIDE" \
  python3 - "$raw" "$OUT_JSON" <<'PY'
import json, os, sys
raw_path, out_path = sys.argv[1], sys.argv[2]
try:
    with open(raw_path) as fh:
        raw = json.load(fh)
except Exception:
    raw = {}
if not isinstance(raw, dict):
    raw = {}

def num(v):
    try:
        if v is None or v == "":
            return 0
        return int(v)
    except Exception:
        try:
            return int(float(v))
        except Exception:
            return 0

usage = raw.get("usage") if isinstance(raw.get("usage"), dict) else {}
raw_in = num(usage.get("input_tokens"))
raw_out = num(usage.get("output_tokens"))
if "cache_read_input_tokens" in usage:
    cached = num(usage.get("cache_read_input_tokens"))
else:
    cached = num(usage.get("cache_read"))
if "cache_creation_input_tokens" in usage:
    cache_write = num(usage.get("cache_creation_input_tokens"))
else:
    cache_write = num(usage.get("cache_creation"))
reasoning = num(usage.get("reasoning_tokens"))
if "reasoning_tokens" not in usage:
    reasoning = num(usage.get("reasoning"))
total_in = raw_in + cached + cache_write
total = total_in + raw_out
session = raw.get("session_id")
if not isinstance(session, str) or not session:
    session = None
raw_class = (os.environ.get("DR_ERROR_CLASS") or "").strip()
if not raw_class:
    errs = os.environ.get("DR_ERRORS") or ""
    if errs.startswith("error_class="):
        raw_class = errs.split(" ", 1)[0].split("=", 1)[1].strip()
err_class = raw_class or None
version = os.environ.get("DRIVER_VERSION") or None
tool_bin = os.environ.get("TOOL_BIN") or None
model = os.environ.get("MODEL") or None
try:
    attempts = int(os.environ.get("ATTEMPTS_INSIDE") or "0")
except Exception:
    attempts = 0
doc = {
    "schema": "driver-result/v1",
    "team": os.environ.get("ORCH_TEAM") or "team1",
    "driver": "claude",
    "driver_version": version,
    "tool_bin": tool_bin,
    "provider": "anthropic",
    "model": model,
    "profile": None,
    "status": os.environ.get("DR_STATUS") or "failed",
    "error_class": err_class,
    "summary": os.environ.get("DR_SUMMARY") or "",
    "errors": os.environ.get("DR_ERRORS") or "",
    "tokens": {
        "input": total_in,
        "cached_input": cached,
        "cache_write_input": cache_write,
        "output": raw_out,
        "reasoning": reasoning,
        "total": total,
    },
    "cost": {
        "usd": None,
        "source": "not_priced",
        "price_table_version": None,
        "long_context_multiplier_applied": False,
    },
    "attempts_inside_driver": attempts,
    "session_id": session,
    "started_at": os.environ.get("DR_STARTED_AT") or None,
    "ended_at": os.environ.get("DR_ENDED_AT") or None,
}
with open(out_path, "w") as fh:
    json.dump(doc, fh)
    fh.write("\n")
PY
  local rc=$?
  rm -f "$raw"
  return "$rc"
}

if [ ! -d "$WT" ]; then
  DR_ERRORS="error_class=infra claude driver worktree missing: $WT"
  DR_SUMMARY="Claude driver failed (infra, not a task defect)"
  write_driver_result
  exit 1
fi
cd "$WT" || {
  DR_ERRORS="error_class=infra claude driver could not cd to $WT"
  DR_SUMMARY="Claude driver failed (infra, not a task defect)"
  write_driver_result
  exit 1
}
if [ ! -f "$PROMPT_FILE" ]; then
  DR_ERRORS="error_class=infra claude driver prompt file missing"
  DR_SUMMARY="Claude driver failed (infra, not a task defect)"
  write_driver_result
  exit 1
fi
PROMPT="$(python3 -c 'import pathlib,sys; sys.stdout.write(pathlib.Path(sys.argv[1]).read_text())' "$PROMPT_FILE")"

# Recorded before the model call so that call stays the last claude invocation
# (argv captures keep the real -p line).
DRIVER_VERSION="$(timeout 10 claude --version 2>/dev/null | head -1 || true)"
TOOL_BIN="$(command -v claude 2>/dev/null || true)"

# ── Permission policy ────────────────────────────────────────────────────────
# Replaces --dangerously-skip-permissions with an explicit allow/deny policy so
# the agent can do normal dev work (git/npm/tsc/python/file edits) but CANNOT
# exfiltrate (curl/wget/ssh/scp/nc), read secrets (.env, ~/.ssh, doppler), or
# run destructive/privileged commands. `deny` always wins over `allow`.
#
# The settings file lives OUTSIDE the worktree (so it's never committed) and is
# passed via --settings (highest precedence). Rollout is env-gated per the
# CLAUDE.md "framework change → staging first" rule. The orchestrator is LIVE,
# so the DEFAULT preserves current behavior; flip the env in Doppler to enforce
# after validating on one server (a headless permission prompt would hang a slot
# until the SSH timeout, so prove the allow-list is complete before fleet-wide):
#   CLAUDE_PERMISSION_MODE=bypass       (default) — current behavior (skip perms)
#   CLAUDE_PERMISSION_MODE=acceptEdits            — enforce allow/deny policy
#   CLAUDE_PERMISSION_MODE=dontAsk                — strict fail-closed (deny, no prompt)
#
# ── What the two enforcing modes ACTUALLY do (measured 2026-09-15, claude CLI
#    2.1.273, against this exact policy file — not inferred) ─────────────────
#   acceptEdits : the `allow` list is NOT a reliable whitelist for Bash.
#                 `rm -rf dist` is in neither `allow` nor `deny`, and RAN — no
#                 prompt, no denial. But do NOT generalise that to "acceptEdits
#                 enforces nothing": `dd if=/dev/zero of=...` and `tar -cf ...`,
#                 equally unlisted, were DENIED under the same mode. So the CLI
#                 appears to carry an internal, undocumented carve-out for
#                 certain commands (at least `rm`, and `hostname`) rather than a
#                 general absence of enforcement. What is safe to rely on:
#                 `deny` always bites, and an unlisted command MAY run. Treat
#                 acceptEdits as "bypass minus the deny list, plus an
#                 unspecified extra" — not as a whitelist.
#                 Externally-reaching tools are still gated: WebFetch denied.
#                 Unexplained rather than assumed absent: `hostname` ran
#                 unprompted even under dontAsk, which looks like a separate
#                 inert-command carve-out. Nobody has read the CLI source for
#                 either carve-out; both are black-box observations.
#   dontAsk     : the `allow` list IS a whitelist. The same `rm -rf dist2` was
#                 DENIED in 7 seconds, recorded in permission_denials, directory
#                 left in place.
#   NEITHER MODE HUNG. The header's warning below about a headless prompt
#   hanging a slot until the SSH timeout did not reproduce on this CLI version;
#   denials came back clean and fast in both modes. That lowers the cost of
#   flipping the env — but agents/setup-server.sh installs @anthropic-ai/
#   claude-code UNPINNED, so re-measure against the version actually on the box
#   before trusting it fleet-wide.
#
# ── What this policy cannot do, stated plainly ──────────────────────────────
# `Bash(python3 *)` and `Bash(node *)` are in `allow` and are REQUIRED (the
# prompt above tells the agent to run python3 -m py_compile; npm/npx run
# arbitrary package scripts). An interpreter is a general-purpose file-read and
# process-spawn primitive, so the allow list is not a containment boundary.
# Measured: `node -e "...readFileSync(...)"` ran with permission_denials EMPTY.
# The same prompt aimed at .env was refused — but by the MODEL, not the policy,
# and model judgment is not a control. What the deny list does buy is real and
# worth keeping: the direct network-egress verbs and the obvious secret paths
# are blocked, including via head/grep/sed/awk (all four were denied against a
# canary .env — the engine matches the path, not just the verb).
# Do NOT add Bash(bash *), Bash(sh *), Bash(xargs *), Bash(timeout *) or
# Bash(tar *) to `allow`: each is a launcher that would void the list wholesale.
PERM_MODE="${CLAUDE_PERMISSION_MODE:-bypass}"
SETTINGS_FILE="$HOME/.config/orchestrator/claude-settings.json"
mkdir -p "$(dirname "$SETTINGS_FILE")"
# Atomic write. Up to 3 slots share this box and this path is FIXED, so a plain
# `cat >` truncate-in-place lets a peer read a half-written file — and `claude
# -p` SILENTLY IGNORES a settings file that fails validation (documented in
# `claude --help`), i.e. the policy would vanish with no error. The trust stamp
# for ~/.claude.json above takes the same precaution for the same reason.
_SETTINGS_TMP="${SETTINGS_FILE}.$$.tmp"
cat > "$_SETTINGS_TMP" <<'JSON'
{
  "permissions": {
    "allow": [
      "Read", "Edit", "Write", "Glob", "Grep",
      "Bash(git *)",
      "Bash(npm *)", "Bash(npx *)", "Bash(pnpm *)", "Bash(yarn *)", "Bash(node *)",
      "Bash(python *)", "Bash(python3 *)", "Bash(pip *)", "Bash(pip3 *)",
      "Bash(pytest *)", "Bash(ruff *)", "Bash(mypy *)",
      "Bash(tsc *)", "Bash(eslint *)", "Bash(prettier *)", "Bash(vite *)",
      "Bash(ls *)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)",
      "Bash(grep *)", "Bash(rg *)", "Bash(find *)", "Bash(wc *)",
      "Bash(sort *)", "Bash(uniq *)", "Bash(diff *)",
      "Bash(mkdir *)", "Bash(cp *)", "Bash(mv *)", "Bash(touch *)",
      "Bash(echo *)", "Bash(sed *)", "Bash(awk *)",
      "Bash(cd *)", "Bash(pwd)", "Bash(test *)", "Bash(env)",
      "Bash(printf *)", "Bash(which *)",
      "Bash(date *)", "Bash(tr *)", "Bash(cut *)",
      "Bash(basename *)", "Bash(dirname *)", "Bash(true)"
    ],
    "deny": [
      "Bash(curl *)", "Bash(wget *)",
      "Bash(ssh *)", "Bash(scp *)", "Bash(sftp *)", "Bash(rsync *)",
      "Bash(nc *)", "Bash(ncat *)", "Bash(telnet *)",
      "Bash(doppler *)", "Bash(sudo *)",
      "Bash(cat *.env*)", "Bash(cat *secret*)", "Bash(cat *.pem)",
      "Bash(cat ~/.ssh/*)", "Bash(cat ~/.aws/*)",
      "Read(.env)", "Read(.env.*)", "Read(**/.env)", "Read(**/.env.*)",
      "Read(~/.ssh/**)", "Read(~/.aws/**)", "Read(~/.config/doppler/**)",
      "Read(**/id_rsa*)", "Read(**/*.pem)",
      "WebFetch", "WebSearch",
      "Bash(git push origin master)", "Bash(git push origin main)",
      "Bash(git push --force *)", "Bash(git push -f *)"
    ]
  }
}
JSON
mv -f "$_SETTINGS_TMP" "$SETTINGS_FILE"

# ── Model selection by complexity (cost control — #5) ────────────────────────
# Default the heavy coding model to the task's complexity tier; override with
# CODING_MODEL to pin a single model fleet-wide.
# Resolved from Doppler FIRST: this script runs on the box outside
# `doppler run --`, so a value set in Doppler is NOT in the environment here.
# Reading only $CODING_MODEL made the documented fleet-wide pin silently inert
# (2026-09-14). Env var still wins if the caller exported one.
_PINNED_MODEL="$(doppler secrets get CODING_MODEL --plain 2>/dev/null || echo "${CODING_MODEL:-}")"
case "$COMPLEXITY" in
  complex) MODEL="${_PINNED_MODEL:-claude-opus-4-8}" ;;
  *)       MODEL="${_PINNED_MODEL:-claude-sonnet-4-6}" ;;
esac

# ── Run Claude CLI headless ──────────────────────────────────────────────────
# Secret narrowing rides the SAME env gate as the permission policy — no second
# flag. On bypass the invocation below is byte-identical to what it always was.
#
# This script is NOT run under `doppler run --` (see the CODING_MODEL comment
# above, which is load-bearing: a Doppler value is not in this environment). So
# there is no whole-config injection to undo here. What the agent DOES inherit
# is everything ~/.env, ~/.profile and ~/.bashrc export — they are sourced with
# `set -a` at the top of this file, so every one of those values is exported
# into claude. `Bash(env)` is in the allow list, which makes that inheritance
# directly readable by the agent.
# GITHUB_TOKEN is stripped too: the runner's own push happens outside this
# invocation, and git inside the worktree still authenticates because
# git-credential-doppler falls back to `doppler secrets get` — a helper git
# spawns itself, which the Bash(doppler *) deny rule does not touch.
if [ "$PERM_MODE" = "bypass" ]; then
  PERM_ARGS=(--dangerously-skip-permissions)
else
  PERM_ARGS=(--permission-mode "$PERM_MODE" --settings "$SETTINGS_FILE")
fi
log "Running Claude: model=$MODEL perm_mode=$PERM_MODE"
_claude_err="$(mktemp)"
if [ "$PERM_MODE" = "bypass" ]; then
  CLAUDE_OUT="$(claude -p "$PROMPT" --model "$MODEL" --output-format json "${PERM_ARGS[@]}" 2>"$_claude_err")"
  CLAUDE_RC=$?
else
  CLAUDE_OUT="$(env -u NODE_SECRET -u DOPPLER_TOKEN -u GITHUB_TOKEN \
      -u DATABASE_URL -u TENANT_DATABASE_URL -u OPEN_MODEL_API_KEY \
      claude -p "$PROMPT" --model "$MODEL" --output-format json "${PERM_ARGS[@]}" 2>"$_claude_err")"
  CLAUDE_RC=$?
fi

cat "$_claude_err" >> "$LOG" 2>/dev/null || true
cat "$_claude_err" >&2 || true
rm -f "$_claude_err"

# Parse claude's JSON result into one record: is_error, result, input_tok,
# output_tok, joined by a unit separator. Tab is IFS whitespace, so an empty
# result (or the non-JSON fallback's empty field) collapsed and IS_ERROR
# swallowed the rest of the line. Both producers below use \x1f. The only
# consumer is the IFS=$'\x1f' read immediately under them.
CLAUDE_PARSED="$(printf '%s' "$CLAUDE_OUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("true\x1f\x1f0\x1f0"); sys.exit(0)
is_error = str(d.get("is_error", True)).lower()
# Unit separator, not tab. Tab is IFS whitespace, so an empty result
# (error_max_turns) collapsed the next fields and the back-compat token
# integer became the input count alone. That was a master parse bug.
result = (d.get("result") or "")[:1000].replace("\n", " ").replace("\t", " ").replace("\x1f", " ")
u = d.get("usage") or {}
print("\x1f".join([is_error, result, str(u.get("input_tokens", 0) or 0), str(u.get("output_tokens", 0) or 0)]))
' 2>/dev/null)"
IFS=$'\x1f' read -r IS_ERROR RESULT_TEXT IN_TOK OUT_TOK <<< "$CLAUDE_PARSED"
TOKENS=$(( ${IN_TOK:-0} + ${OUT_TOK:-0} ))

# ── Tool-denial visibility ───────────────────────────────────────────────────
# A tool refused by the permission policy does NOT make claude exit non-zero and
# does NOT set is_error: measured, a denied Bash returns is_error=false with the
# assistant asking for approval. The run then dies further down as "No commits
# produced on $BRANCH" — which is indistinguishable from an Anthropic API or
# credit failure, and that misdiagnosis has burned repeated sessions on the
# status page. So name it, from a structural signal rather than a text grep:
# `claude --output-format json` emits a top-level "permission_denials" array,
# one entry per refusal, carrying tool_name and tool_input (verified against
# claude CLI 2.1.273, for both --disallowedTools and a --settings deny list).
DENIED_TOOLS="$(printf '%s' "$CLAUDE_OUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = None
out = []
for e in ((d or {}).get("permission_denials") or []):
    if not isinstance(e, dict):
        continue
    name = e.get("tool_name") or "?"
    ti = e.get("tool_input") if isinstance(e.get("tool_input"), dict) else {}
    detail = ti.get("command") or ti.get("file_path") or ti.get("url") or ""
    out.append("%s: %s" % (name, str(detail)[:120]) if detail else name)
print(" | ".join(out[:10]))
' 2>/dev/null)"

DENY_NOTE=""
if [ -n "$DENIED_TOOLS" ]; then
  DENY_NOTE="TOOL DENIED BY THE RUNNER PERMISSION POLICY (CLAUDE_PERMISSION_MODE=$PERM_MODE, $SETTINGS_FILE): ${DENIED_TOOLS}. This is NOT an Anthropic API or credit failure — do not go read the status page. Widen the allow list in orchestrator-run.sh, or set CLAUDE_PERMISSION_MODE=bypass to restore unconfined runs."
  log "$DENY_NOTE"
fi

DR_STATUS="success"
DR_ERRORS="$DENY_NOTE"
DR_SUMMARY="$RESULT_TEXT"
DR_ERROR_CLASS=""
if [ "$CLAUDE_RC" -ne 0 ] || [ "${IS_ERROR:-true}" = "true" ]; then
  DR_STATUS="failed"
  DR_ERRORS="${DENY_NOTE:+$DENY_NOTE }Claude CLI error: $RESULT_TEXT"
  DR_SUMMARY="Agent run failed"
  # A model failure is a task defect. 429 and credit exhaustion are quota:
  # the orchestrator's detectApiExhaustion reads the errors string, so the
  # raw text has to stay in that string even when the JSON parse dropped it.
  # Scan the model text. A JSON blob's duration_ms (14290), a session id
  # that contains 4290, or the words "rate limiter" are not a 429. When
  # stdout is not JSON, RESULT_TEXT is empty and the CLI text is the
  # stdout itself — scan that, and do not paste a JSON blob into errors.
  DR_ERROR_CLASS="task"
  _quota_re='\b429\b|\brate[-_ ]?limit(ed)?\b|\btoo many requests\b|\bcredit balance is too low\b|\binsufficient credit\b|\bout of credits\b|\bcredit exhaust|\busage limits\b'
  _quota_src="$RESULT_TEXT"
  if ! printf '%s' "$CLAUDE_OUT" | python3 -c 'import sys,json; json.load(sys.stdin)' >/dev/null 2>&1; then
    _quota_src="$CLAUDE_OUT"
  fi
  if printf '%s\n' "$_quota_src" | grep -Eqi "$_quota_re"; then
    DR_ERROR_CLASS="quota"
    if ! printf '%s' "$DR_ERRORS" | grep -Eqi "$_quota_re"; then
      _snip="$(printf '%s' "$_quota_src" | tr '\n\t\r' '   ' | head -c 400)"
      DR_ERRORS="${DR_ERRORS} ${_snip}"
    fi
  fi
fi
ATTEMPTS_INSIDE=1

write_driver_result
exit "$CLAUDE_RC"

#!/usr/bin/env bash
# run-python-hook.sh GUARD.py
#
# PreToolUse adapter for the Python guards in this directory.
#
# .claude/settings.json must invoke this with a plain command and no $VAR
# or ${VAR}. Grok expands those in the hook command before bash, and an
# unset one is a hard failure ("required env var(s) not set") even though
# the tool call still proceeds. Lookups and the Grok-to-Claude field
# rewrite live here, where the hook runner does not scan them.
#
# Fail-open: missing guard, missing interpreter, or any adapter error
# exits 0 with no output. The guard's own stdout and exit code pass through.
set -u

name="${1:-}"
here="$(cd "$(dirname "$0")" && pwd)"
guard="${here}/${name}"
if [ -z "$name" ] || [ ! -f "$guard" ]; then
  exit 0
fi
py="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
if [ -z "$py" ]; then
  exit 0
fi

adapt=$(cat <<'PY'
import json, subprocess, sys

guard = sys.argv[1]
# Grok tool names -> the Claude names the guards already match on.
names = {
    "run_terminal_command": "Bash",
    "read_file": "Read",
    "search_replace": "Edit",
    "write": "Write",
    "grep": "Grep",
    "list_dir": "Glob",
}
raw = sys.stdin.buffer.read()
try:
    payload = json.loads(raw.decode("utf-8")) if raw.strip() else {}
except Exception:
    payload = None
if isinstance(payload, dict):
    incoming = payload.get("tool_input")
    if not isinstance(incoming, dict):
        incoming = payload.get("toolInput")
    tool_input = dict(incoming) if isinstance(incoming, dict) else {}
    grok_name = payload.get("toolName") if isinstance(payload.get("toolName"), str) else ""
    existing = payload.get("tool_name") if isinstance(payload.get("tool_name"), str) else ""
    claude_name = existing or names.get(grok_name, grok_name)
    # read_file sends target_file; the guards read file_path. Only Read is
    # patched, so a later updatedInput cannot grow a key the tool schema rejects.
    if claude_name == "Read" and not isinstance(tool_input.get("file_path"), str):
        target = tool_input.get("target_file")
        if isinstance(target, str) and target.strip():
            tool_input["file_path"] = target
    if claude_name == "Glob" and not isinstance(tool_input.get("path"), str):
        target = tool_input.get("target_directory")
        if isinstance(target, str) and target.strip():
            tool_input["path"] = target
    payload["tool_name"] = claude_name
    payload["tool_input"] = tool_input
    raw = json.dumps(payload).encode("utf-8")
try:
    proc = subprocess.run([sys.executable, guard], input=raw)
except Exception:
    sys.exit(0)
sys.exit(proc.returncode if proc.returncode is not None else 0)
PY
)
exec "$py" -c "$adapt" "$guard"

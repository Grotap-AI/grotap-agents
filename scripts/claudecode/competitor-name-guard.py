#!/usr/bin/env python3
"""competitor-name-guard.py — Claude Code PreToolUse hook (owner rule 2026-09-10).

The competitor RFID vendor whose tags Manor View's field stock carries is NEVER
named in any work product: code, comments, docs, commit messages, release
notes, PR text, artifacts. Write "Competitor RFID Software" instead. This hook
enforces that mechanically on everything Claude writes:

  Write   -> rewrites `content`
  Edit    -> rewrites `new_string` (never `old_string`, so the match still lands)
  Bash    -> rewrites the command text ONLY for git commit / git tag / gh pr /
             gh release, i.e. human-facing prose; scans like `grep -i <name>`
             pass through untouched
  (Artifact publishes a file that Write already produced, so it is covered.)

Replacement by case of the matched core token:
  Capitalised prose ("Xxxxx", "Xxxxx Technologies", "Xxxxx Tec", "Xxxxx RFID")
      -> "Competitor RFID Software"
  ALL CAPS identifier fragment (_XXXXX_SHAPE)  -> "COMPETITOR"
  lowercase token ('xxxxx', a stored key)      -> "competitor"

Carry-over exemption: a lowercase/identifier token that ALREADY exists in the
text being edited (Edit.old_string, or the current on-disk file for Write) is
left alone — `source_system='<key>'` is a stored value on 24,671 tenant rows
and must not be renamed in code before the data migration renames the rows.
Newly introduced tokens are always rewritten.

Contract: never blocks, never raises; on any doubt exit 0 with no output.
Reports via systemMessage (user) + additionalContext (model) when it rewrote.

The vendor name is assembled at runtime so this file itself passes the
pre-commit guard (scripts/git-hooks/pre-commit) and `git grep`.
"""
from __future__ import annotations

import json
import os
import re
import sys

REPLACEMENT = "Competitor RFID Software"
_CORE = "ar" + "bre"  # assembled so the literal never appears in the repo

# core token, optional vendor-suffix words, optional "RFID"; not glued to letters
_PATTERN = re.compile(
    r"(?<![A-Za-z])(" + _CORE + r")"
    r"(?:[ _\-]*(?:technolog(?:y|ies)|tec(?:h)?))?"
    r"(?:[ _\-]*rfid)?"
    r"(?![a-z])",
    re.IGNORECASE,
)
_PROSE_TOOLS = re.compile(
    r"\bgit\s+(?:commit|tag|notes)\b|\bgh\s+(?:pr|release|issue)\b", re.IGNORECASE
)


def _replacement_for(match: re.Match) -> str:
    core = match.group(1)
    if core.isupper():
        return "COMPETITOR"
    if core.islower():
        return "competitor"
    return REPLACEMENT


def _tokens(text: str) -> set[str]:
    return {m.group(0) for m in _PATTERN.finditer(text or "")}


def rewrite(text: str, exempt: set[str] | None = None) -> tuple[str, int]:
    """Return (new_text, count). Matches whose exact text is in `exempt` stay."""
    exempt = exempt or set()
    count = 0

    def _sub(m: re.Match) -> str:
        nonlocal count
        if m.group(0) in exempt:
            return m.group(0)
        count += 1
        return _replacement_for(m)

    return _PATTERN.sub(_sub, text or ""), count


def _existing_file_tokens(path: str) -> set[str]:
    try:
        if path and os.path.isfile(path):
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                return _tokens(fh.read())
    except Exception:
        pass
    return set()


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return 0

    updated = dict(tool_input)
    total = 0

    if tool == "Write":
        content = tool_input.get("content")
        if isinstance(content, str):
            exempt = _existing_file_tokens(tool_input.get("file_path") or "")
            exempt = {t for t in exempt if not t[0].isupper() or t.isupper()}  # prose never exempt
            new, n = rewrite(content, exempt)
            if n:
                updated["content"] = new
                total += n
    elif tool == "Edit":
        new_string = tool_input.get("new_string")
        if isinstance(new_string, str):
            exempt = _tokens(tool_input.get("old_string") or "")
            exempt = {t for t in exempt if not t[0].isupper() or t.isupper()}
            new, n = rewrite(new_string, exempt)
            if n:
                updated["new_string"] = new
                total += n
    elif tool == "Bash":
        cmd = tool_input.get("command")
        if isinstance(cmd, str) and _PROSE_TOOLS.search(cmd):
            new, n = rewrite(cmd)
            if n:
                updated["command"] = new
                total += n
    else:
        return 0

    if not total:
        return 0

    note = (
        f"competitor-name-guard: rewrote {total} competitor-vendor mention(s) to "
        f"'{REPLACEMENT}' in this {tool} call (owner rule 2026-09-10 — the vendor is "
        f"never named in code, docs, releases or artifacts)."
    )
    out = {
        "systemMessage": note,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": note,
            "updatedInput": updated,
            "additionalContext": note + " The written content differs from what you sent; re-read before editing the same lines.",
        },
    }
    sys.stdout.write(json.dumps(out))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)

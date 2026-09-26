#!/usr/bin/env python3
"""Prompt-cache placement for Anthropic calls in this repo.

Direct Messages API calls get at most four ephemeral cache breakpoints, in
order: tool definitions, the system prompt, then large stable context. The
breakpoint is attached only once the prefix up to that point meets the
model minimum (1024 tokens for Sonnet/Opus, 2048 for Haiku). Per-request
content — case ids, diffs, timestamps — stays after that prefix and is
never marked.

Claude Code CLI caching is automatic. This module also builds the
orchestrator user prompt so its stable rules precede the per-case payload,
and it reads cache_creation_input_tokens / cache_read_input_tokens off CLI
usage payloads.
"""

from __future__ import annotations

import json
import sys
from typing import Any, Callable

# Documented floors. A breakpoint on a shorter prefix is ignored by the API
# and still billed as a cache write when the API does accept it, so stay at
# or above these before marking.
SONNET_OPUS_MIN_TOKENS = 1024
HAIKU_MIN_TOKENS = 2048
MAX_BREAKPOINTS = 4

TokenCounter = Callable[[str], int]


def min_cache_tokens(model: str) -> int:
    name = (model or "").lower()
    if "haiku" in name:
        return HAIKU_MIN_TOKENS
    return SONNET_OPUS_MIN_TOKENS


def estimate_tokens(text: str) -> int:
    """Cheap floor estimate: 4 characters per token, rounded up.

    Over-estimating marks a prefix the API may still ignore. Under-estimating
    would skip a prefix the API would have cached. Rounding up is the safer
    direction. Callers with a real tokenizer can pass their own counter.
    """
    if not text:
        return 0
    return (len(text) + 3) // 4


# Byte-stable across runs. Per-case titles, diffs, case ids, and timestamps
# are appended after this block by build_orchestrator_prompt().
STABLE_PREFIX = """\
You are an autonomous engineer working in an isolated git worktree on the grotap-platform repo.

## Rules
- Follow the repo CLAUDE.md and agents/GLOBAL.md rules exactly.
- Make the minimal correct change. Commit your work with git (do NOT push — the runner pushes).
- Never symlink node_modules (or any path) from the shared ~/grotap-platform clone into this worktree. If a package needs deps, run 'npm ci' inside that package here — the shared install may be stale and a symlink breaks build verification.
- Before finishing, validate: run 'npx tsc --noEmit' in any frontend/TS package you changed, and 'python3 -m py_compile' on any backend .py file you changed.
- If you cannot complete the task, explain why clearly."""


def _s(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def _attempt(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 1


def build_orchestrator_prompt(payload: dict) -> str:
    """User prompt for `claude -p`. Stable rules first, request fields after.

    case_id, branch, and attempt are not interpolated into the stable prefix.
    They only appear if the caller already put them in a per-request field
    (title, context, requirements, plan, context pack, or prior errors).
    """
    title = _s(payload.get("title"))
    context = _s(payload.get("context"))
    requirements = _s(payload.get("requirements"))
    plan = _s(payload.get("plan"))
    context_pack = _s(payload.get("context_pack"))
    attempt = _attempt(payload.get("attempt", 1))
    errors = payload.get("prior_errors") or []
    if not isinstance(errors, list):
        errors = []
    prior = "\n---\n".join(_s(item) for item in errors)

    variable = f"# Task: {title}\n\n## Context\n{context}\n\n## Requirements\n{requirements}"
    if context_pack:
        variable += (
            "\n\n## Platform Knowledge (grounded from our docs — prefer this over assumptions)\n"
            + context_pack
        )
    if plan:
        variable += (
            "\n\n## Execution Plan (from triage — follow it unless it's clearly wrong)\n"
            + plan
        )
    if attempt > 1 and prior:
        variable += (
            f"\n\n## This is retry attempt {attempt}. The previous attempt(s) failed. "
            f"Fix these issues (real output below):\n{prior}"
        )
    return STABLE_PREFIX + "\n\n" + variable


def _ephemeral() -> dict:
    return {"type": "ephemeral"}


def _text_blocks(value: Any) -> list[dict]:
    if value is None:
        return []
    if isinstance(value, str):
        if value == "":
            return []
        return [{"type": "text", "text": value}]
    if isinstance(value, list):
        blocks: list[dict] = []
        for part in value:
            if isinstance(part, str):
                if part:
                    blocks.append({"type": "text", "text": part})
            elif isinstance(part, dict):
                cleaned = {k: v for k, v in part.items() if k != "cache_control"}
                blocks.append(cleaned)
        return blocks
    return [{"type": "text", "text": str(value)}]


def _block_text(block: dict) -> str:
    if not isinstance(block, dict):
        return ""
    text = block.get("text")
    if isinstance(text, str):
        return text
    return json.dumps(block, sort_keys=True, separators=(",", ":"))


def _strip_message(message: Any) -> Any:
    if not isinstance(message, dict):
        return message
    copied = dict(message)
    content = copied.get("content")
    if isinstance(content, list):
        cleaned = []
        for part in content:
            if isinstance(part, dict):
                cleaned.append({k: v for k, v in part.items() if k != "cache_control"})
            else:
                cleaned.append(part)
        copied["content"] = cleaned
    return copied


def apply_cache_control(
    body: dict,
    token_counter: TokenCounter | None = None,
) -> dict:
    """Return a Messages API body with ephemeral breakpoints on the stable prefix.

    `stable_context` is an input-only field (string or list of text blocks).
    It is inserted at the start of the first user message, ahead of whatever
    that message already held, and is not sent as its own API field.

    Content already in `messages` is per-request and is never marked.
    """
    counter = token_counter or estimate_tokens
    minimum = min_cache_tokens(str(body.get("model") or ""))

    tools_in = body.get("tools")
    tools: list[dict] = []
    if isinstance(tools_in, list):
        for tool in tools_in:
            if isinstance(tool, dict):
                tools.append({k: v for k, v in tool.items() if k != "cache_control"})

    system_blocks = _text_blocks(body.get("system")) if "system" in body else []
    stable_blocks = _text_blocks(body.get("stable_context"))

    marks = 0
    cumulative = 0

    def note(tokens: int) -> None:
        nonlocal cumulative
        cumulative += tokens

    def mark(block: dict) -> None:
        nonlocal marks
        if marks >= MAX_BREAKPOINTS:
            return
        block["cache_control"] = _ephemeral()
        marks += 1

    if tools:
        tool_tokens = 0
        for tool in tools:
            tool_tokens += counter(json.dumps(tool, sort_keys=True, separators=(",", ":")))
        note(tool_tokens)
        if cumulative >= minimum:
            mark(tools[-1])

    if system_blocks:
        note(sum(counter(_block_text(block)) for block in system_blocks))
        if cumulative >= minimum:
            mark(system_blocks[-1])

    if stable_blocks:
        note(sum(counter(_block_text(block)) for block in stable_blocks))
        if cumulative >= minimum:
            mark(stable_blocks[-1])

    messages_in = body.get("messages")
    messages: list[Any] = []
    if isinstance(messages_in, list):
        messages = [_strip_message(message) for message in messages_in]

    if stable_blocks and messages:
        for message in messages:
            if isinstance(message, dict) and message.get("role") == "user":
                existing = _text_blocks(message.get("content"))
                # A string user message with nothing stable in front of it
                # stays a string. Once stable context is prepended, both
                # halves are blocks so the breakpoint can sit between them.
                message["content"] = stable_blocks + existing
                break
        else:
            messages.insert(0, {"role": "user", "content": stable_blocks})
    elif stable_blocks:
        messages = [{"role": "user", "content": stable_blocks}]

    result: dict[str, Any] = {}
    for key, value in body.items():
        if key == "stable_context":
            continue
        result[key] = value
    if isinstance(tools_in, list):
        result["tools"] = tools
    if "system" in body:
        original = body.get("system")
        marked = any(isinstance(block, dict) and "cache_control" in block for block in system_blocks)
        if isinstance(original, str) and not marked and len(system_blocks) <= 1:
            result["system"] = original
        else:
            result["system"] = system_blocks
    if "messages" in body or stable_blocks:
        result["messages"] = messages
    return result


def build_probe_body(model: str) -> dict:
    """Smallest messages call the fleet probe sends.

    One output token, no tools, no system prompt, no stable context. That is
    under both cache minimums, so apply_cache_control attaches nothing.
    Padding this call up to the minimum would make the probe more expensive,
    which is the opposite of what it is for.
    """
    return apply_cache_control(
        {
            "model": model,
            "max_tokens": 1,
            "messages": [{"role": "user", "content": "hi"}],
        }
    )


def _as_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _cache_pair(usage: Any) -> tuple[int | None, int | None]:
    """Return (creation, read) or None for a side the payload does not report."""
    if not isinstance(usage, dict):
        return None, None
    creation: int | None
    read: int | None
    if "cache_creation_input_tokens" in usage or "cacheCreationInputTokens" in usage:
        creation = _as_int(
            usage.get("cache_creation_input_tokens", usage.get("cacheCreationInputTokens"))
        )
    else:
        nested = usage.get("cache_creation", usage.get("cacheCreation"))
        if isinstance(nested, dict):
            creation = _as_int(nested.get("ephemeral_5m_input_tokens")) + _as_int(
                nested.get("ephemeral_1h_input_tokens")
            )
        else:
            creation = None
    if "cache_read_input_tokens" in usage or "cacheReadInputTokens" in usage:
        read = _as_int(usage.get("cache_read_input_tokens", usage.get("cacheReadInputTokens")))
    else:
        read = None
    return creation, read


def extract_usage(payload: dict) -> tuple[int, int, int, int]:
    """input, output, cache_creation_input_tokens, cache_read_input_tokens.

    Prefers the top-level `usage` object Claude Code and the Messages API
    both emit. When that object omits the cache fields, sums `modelUsage`
    (camelCase) so a 24-hour hit rate can still be computed.
    """
    usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
    input_tokens = _as_int(usage.get("input_tokens", usage.get("inputTokens")))
    output_tokens = _as_int(usage.get("output_tokens", usage.get("outputTokens")))
    creation, read = _cache_pair(usage)
    if creation is None or read is None:
        summed_c = 0
        summed_r = 0
        saw = False
        model_usage = payload.get("modelUsage")
        if isinstance(model_usage, dict):
            for part in model_usage.values():
                part_c, part_r = _cache_pair(part)
                if part_c is None and part_r is None:
                    continue
                saw = True
                summed_c += part_c or 0
                summed_r += part_r or 0
        if creation is None:
            creation = summed_c if saw else 0
        if read is None:
            read = summed_r if saw else 0
    return input_tokens, output_tokens, creation, read


def parse_cli_usage_line(raw: str) -> str:
    """Tab line: is_error, result, input, output, cache_creation, cache_read.

    Matches the previous orchestrator parser for the first four fields
    (is_error defaults to true, result clipped to 1000 chars, newlines and
    tabs stripped) and appends the two cache counters.
    """
    try:
        payload = json.loads(raw)
    except Exception:
        return "true\t\t0\t0\t0\t0"
    if not isinstance(payload, dict):
        return "true\t\t0\t0\t0\t0"
    is_error = str(payload.get("is_error", True)).lower()
    result = (payload.get("result") or "")[:1000].replace("\n", " ").replace("\t", " ")
    input_tokens, output_tokens, creation, read = extract_usage(payload)
    return "\t".join(
        [is_error, result, str(input_tokens), str(output_tokens), str(creation), str(read)]
    )


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        sys.stderr.write(
            "usage: anthropic_prompt_cache.py "
            "build-probe-body [--model ID] | build-orchestrator-prompt | parse-cli-usage\n"
        )
        return 2
    command = argv[1]
    if command == "build-probe-body":
        model = "claude-haiku-4-5-20251001"
        args = argv[2:]
        index = 0
        while index < len(args):
            if args[index] == "--model" and index + 1 < len(args):
                index += 1
                model = args[index]
            else:
                sys.stderr.write(f"unknown arg: {args[index]}\n")
                return 2
            index += 1
        json.dump(build_probe_body(model), sys.stdout, separators=(",", ":"))
        return 0
    if command == "build-orchestrator-prompt":
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            sys.stderr.write("prompt payload must be a JSON object\n")
            return 2
        sys.stdout.write(build_orchestrator_prompt(payload))
        return 0
    if command == "parse-cli-usage":
        sys.stdout.write(parse_cli_usage_line(sys.stdin.read()))
        return 0
    sys.stderr.write(f"unknown command: {command}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

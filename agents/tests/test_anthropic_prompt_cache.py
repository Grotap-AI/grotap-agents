#!/usr/bin/env python3
"""Cache-breakpoint placement and Claude prompt prefix stability."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO / "agents" / "scripts" / "anthropic_prompt_cache.py"
HOOK_PATH = REPO / "scripts" / "claudecode" / "session-start-hook.sh"
PROBE_PATH = REPO / "agents" / "scripts" / "fleet-model-probe.sh"
ORCH_PATH = REPO / "agents" / "scripts" / "orchestrator-run.sh"
GATE_PATH = REPO / "agents" / "scripts" / "review-gate-cron.sh"
WRAPPER_PATH = REPO / "scripts" / "claudecode" / "claude-remote-wrapper.sh"
ENV_PATH = REPO / "agents" / "scripts" / "claude-prompt-cache.sh"


def _load():
    spec = importlib.util.spec_from_file_location("anthropic_prompt_cache", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mod = _load()


def _cache_points(body: dict) -> list[tuple]:
    found = []
    for index, tool in enumerate(body.get("tools") or []):
        if isinstance(tool, dict) and "cache_control" in tool:
            found.append(("tools", index, tool["cache_control"]))
    system = body.get("system")
    if isinstance(system, list):
        for index, block in enumerate(system):
            if isinstance(block, dict) and "cache_control" in block:
                found.append(("system", index, block["cache_control"]))
    for mindex, message in enumerate(body.get("messages") or []):
        content = message.get("content") if isinstance(message, dict) else None
        if isinstance(content, list):
            for index, block in enumerate(content):
                if isinstance(block, dict) and "cache_control" in block:
                    found.append(("messages", mindex, index, block["cache_control"]))
    return found


def _by_len(text: str) -> int:
    return len(text)


class CacheControlPlacementTest(unittest.TestCase):
    def test_breakpoints_follow_tools_system_then_stable_context(self):
        long = "t" * 2000
        variable = "case CASE-20260924-575378 at 2026-09-26T18:50:00Z\ndiff --git a/x b/x\n"
        body = {
            "model": "claude-sonnet-4-6",
            "max_tokens": 16,
            "tools": [
                {"name": "read", "description": long},
                {"name": "edit", "description": long},
            ],
            "system": "system " + long,
            "stable_context": "stable docs " + long,
            "messages": [{"role": "user", "content": variable}],
        }
        out = mod.apply_cache_control(body, token_counter=_by_len)
        points = _cache_points(out)
        sections = [point[0] for point in points]
        self.assertEqual(sections, ["tools", "system", "messages"])
        self.assertLessEqual(len(points), 4)
        for point in points:
            self.assertEqual(point[-1], {"type": "ephemeral"})
        self.assertNotIn("cache_control", out["tools"][0])
        self.assertEqual(out["tools"][1]["cache_control"]["type"], "ephemeral")

        content = out["messages"][0]["content"]
        self.assertIsInstance(content, list)
        self.assertGreaterEqual(len(content), 2)
        self.assertIn("stable docs", content[0]["text"])
        self.assertNotIn("CASE-20260924-575378", content[0]["text"])
        self.assertNotIn("2026-09-26T18:50:00Z", content[0]["text"])
        self.assertNotIn("diff --git", content[0]["text"])
        self.assertEqual(content[-1]["text"], variable)
        self.assertNotIn("cache_control", content[-1])
        self.assertNotIn("stable_context", out)

    def test_haiku_minimum_is_higher_than_sonnet(self):
        body = {
            "model": "claude-sonnet-4-6",
            "tools": [{"name": "a", "description": "x" * 100}],
            "system": "s" * 1500,
            "stable_context": "c" * 500,
            "messages": [{"role": "user", "content": "CASE-1"}],
        }
        sonnet = mod.apply_cache_control(body, token_counter=_by_len)
        haiku_body = dict(body, model="claude-haiku-4-5-20251001")
        haiku = mod.apply_cache_control(haiku_body, token_counter=_by_len)

        sonnet_system = sonnet["system"]
        self.assertIsInstance(sonnet_system, list)
        self.assertIn("cache_control", sonnet_system[-1])
        # Under the Haiku floor at the system boundary, so the system string
        # stays unmarked. The stable block after it crosses 2048 and is marked.
        self.assertIsInstance(haiku["system"], str)
        self.assertNotIn("cache_control", haiku["system"])
        self.assertIn("cache_control", haiku["messages"][0]["content"][0])
        self.assertNotIn("cache_control", haiku["messages"][0]["content"][-1])

    def test_real_estimator_respects_published_minimums(self):
        self.assertEqual(mod.min_cache_tokens("claude-sonnet-4-6"), 1024)
        self.assertEqual(mod.min_cache_tokens("claude-opus-4-8"), 1024)
        self.assertEqual(mod.min_cache_tokens("claude-haiku-4-5-20251001"), 2048)
        self.assertEqual(mod.estimate_tokens("a" * 4096), 1024)
        self.assertEqual(mod.estimate_tokens("a" * 4092), 1023)

        sonnet_ok = mod.apply_cache_control(
            {
                "model": "claude-sonnet-4-6",
                "system": "a" * 4096,
                "messages": [{"role": "user", "content": "CASE-1 2026-01-01T00:00:00Z"}],
            }
        )
        sonnet_short = mod.apply_cache_control(
            {
                "model": "claude-sonnet-4-6",
                "system": "a" * 4092,
                "messages": [{"role": "user", "content": "CASE-1 2026-01-01T00:00:00Z"}],
            }
        )
        self.assertIsInstance(sonnet_ok["system"], list)
        self.assertEqual(sonnet_ok["system"][0]["cache_control"], {"type": "ephemeral"})
        self.assertEqual(sonnet_short["system"], "a" * 4092)
        self.assertNotIn("cache_control", json.dumps(sonnet_short))

        haiku_short = mod.apply_cache_control(
            {
                "model": "claude-haiku-4-5-20251001",
                "system": "a" * 4096,
                "messages": [{"role": "user", "content": "hi"}],
            }
        )
        haiku_ok = mod.apply_cache_control(
            {
                "model": "claude-haiku-4-5-20251001",
                "system": "a" * 8192,
                "messages": [{"role": "user", "content": "hi"}],
            }
        )
        self.assertEqual(haiku_short["system"], "a" * 4096)
        self.assertEqual(haiku_ok["system"][0]["cache_control"]["type"], "ephemeral")

    def test_variable_message_is_not_marked_even_when_long(self):
        out = mod.apply_cache_control(
            {
                "model": "claude-sonnet-4-6",
                "messages": [{"role": "user", "content": "CASE-9 " + ("x" * 8000)}],
            },
            token_counter=_by_len,
        )
        self.assertNotIn("cache_control", json.dumps(out))
        self.assertTrue(out["messages"][0]["content"].startswith("CASE-9 "))

    def test_at_most_four_breakpoints(self):
        long = "z" * 3000
        out = mod.apply_cache_control(
            {
                "model": "claude-opus-4-8",
                "tools": [{"name": f"t{i}", "description": long} for i in range(6)],
                "system": ["one " + long, "two " + long],
                "stable_context": ["s1 " + long, "s2 " + long],
                "messages": [{"role": "user", "content": "diff --git a b"}],
            },
            token_counter=_by_len,
        )
        self.assertLessEqual(len(_cache_points(out)), 4)
        self.assertEqual(sum(1 for tool in out["tools"] if "cache_control" in tool), 1)
        self.assertEqual(out["tools"][-1]["cache_control"]["type"], "ephemeral")

    def test_probe_body_stays_under_the_minimum(self):
        body = mod.build_probe_body("claude-haiku-4-5-20251001")
        self.assertEqual(
            body,
            {
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages": [{"role": "user", "content": "hi"}],
            },
        )
        self.assertNotIn("cache_control", json.dumps(body))
        probed = subprocess.check_output(
            [
                "python3",
                str(MODULE_PATH),
                "build-probe-body",
                "--model",
                "claude-haiku-4-5-20251001",
            ],
            text=True,
        )
        self.assertEqual(json.loads(probed), body)


class PrefixStabilityTest(unittest.TestCase):
    def test_orchestrator_prefix_is_byte_stable(self):
        first = mod.build_orchestrator_prompt(
            {
                "case_id": "CASE-20260924-111111",
                "branch": "case-20260924-111111",
                "title": "alpha",
                "context": "CASE-20260924-111111\n2026-09-26T18:50:00Z\ndiff --git a/a b/a",
                "requirements": "do the thing",
                "attempt": 1,
            }
        )
        second = mod.build_orchestrator_prompt(
            {
                "case_id": "CASE-20260924-222222",
                "branch": "case-20260924-222222",
                "title": "beta",
                "context": "CASE-20260924-222222\n2026-01-01T00:00:00Z\ndiff --git a/b b/b",
                "requirements": "do the other thing",
                "plan": "step",
                "context_pack": "docs",
                "attempt": 3,
                "prior_errors": ["boom at 2026-09-26T18:51:00Z"],
            }
        )
        self.assertTrue(first.startswith(mod.STABLE_PREFIX))
        self.assertTrue(second.startswith(mod.STABLE_PREFIX))
        self.assertEqual(first[: len(mod.STABLE_PREFIX)], second[: len(mod.STABLE_PREFIX)])
        prefix = mod.STABLE_PREFIX
        for needle in (
            "CASE-",
            "2026-",
            "diff --git",
            "alpha",
            "beta",
            "retry attempt",
        ):
            self.assertNotIn(needle, prefix)
        tail = first[len(prefix) :]
        self.assertIn("CASE-20260924-111111", tail)
        self.assertIn("2026-09-26T18:50:00Z", tail)
        self.assertIn("diff --git", tail)
        self.assertLess(first.index("# Task:"), first.index("CASE-20260924-111111"))
        self.assertIn("## Rules", prefix)
        self.assertIn("do NOT push", prefix)
        self.assertIn("retry attempt 3", second)
        self.assertNotIn("retry attempt", first)

    def test_cli_prompt_prefix_matches_across_payloads(self):
        def run(payload: dict) -> str:
            return subprocess.check_output(
                ["python3", str(MODULE_PATH), "build-orchestrator-prompt"],
                input=json.dumps(payload),
                text=True,
            )

        left = run({"title": "one", "context": "CASE-AAA 2026-09-26T00:00:00Z", "requirements": "r"})
        right = run({"title": "two", "context": "CASE-BBB 2026-01-02T03:04:05Z", "requirements": "s"})
        self.assertEqual(left[: len(mod.STABLE_PREFIX)], right[: len(mod.STABLE_PREFIX)])
        self.assertNotIn("CASE-AAA", left[: len(mod.STABLE_PREFIX)])


class UsageLoggingTest(unittest.TestCase):
    def test_flat_usage_fields(self):
        line = mod.parse_cli_usage_line(
            json.dumps(
                {
                    "is_error": False,
                    "result": "ok\nline",
                    "usage": {
                        "input_tokens": 3,
                        "output_tokens": 4,
                        "cache_creation_input_tokens": 100,
                        "cache_read_input_tokens": 50,
                    },
                }
            )
        )
        parts = line.split("\t")
        self.assertEqual(parts, ["false", "ok line", "3", "4", "100", "50"])

    def test_nested_cache_creation_and_model_usage_fallback(self):
        creation, read = mod._cache_pair(
            {
                "cache_creation": {
                    "ephemeral_5m_input_tokens": 10,
                    "ephemeral_1h_input_tokens": 5,
                },
                "cache_read_input_tokens": 7,
            }
        )
        self.assertEqual((creation, read), (15, 7))
        input_tokens, output_tokens, creation, read = mod.extract_usage(
            {
                "usage": {"input_tokens": 3, "output_tokens": 4},
                "modelUsage": {
                    "claude-sonnet-4-6": {
                        "inputTokens": 99,
                        "outputTokens": 99,
                        "cacheReadInputTokens": 9,
                        "cacheCreationInputTokens": 8,
                    }
                },
            }
        )
        self.assertEqual((input_tokens, output_tokens, creation, read), (3, 4, 8, 9))

    def test_invalid_cli_payload_is_zeroed(self):
        self.assertEqual(mod.parse_cli_usage_line("not-json"), "true\t\t0\t0\t0\t0")


class ClaudeCliCacheSwitchTest(unittest.TestCase):
    def test_helper_unsets_disable_switches(self):
        script = r"""
set -u
export DISABLE_PROMPT_CACHING=1
export CLAUDE_CODE_DISABLE_PROMPT_CACHING=1
. "$1"
if [ -n "${DISABLE_PROMPT_CACHING+x}" ]; then echo still-set-disable; exit 1; fi
if [ -n "${CLAUDE_CODE_DISABLE_PROMPT_CACHING+x}" ]; then echo still-set-prefixed; exit 1; fi
# unset of an already-absent variable must not trip set -u
. "$1"
echo ok
"""
        out = subprocess.check_output(["bash", "-c", script, "bash", str(ENV_PATH)], text=True)
        self.assertEqual(out.strip(), "ok")

    def test_drivers_source_the_helper_before_claude(self):
        needles = {
            ORCH_PATH: "claude -p ",
            GATE_PATH: "claude -p ",
            WRAPPER_PATH: "claude remote-control",
        }
        for path, needle in needles.items():
            code = "\n".join(
                line
                for line in path.read_text().splitlines()
                if not line.strip().startswith("#")
            )
            self.assertIn("claude-prompt-cache.sh", code, path.name)
            self.assertLess(code.index("claude-prompt-cache.sh"), code.index(needle), path.name)

    def test_probe_builds_the_body_through_the_placer(self):
        text = PROBE_PATH.read_text()
        self.assertIn("build-probe-body", text)
        self.assertNotIn('{"model":"${MODEL}"', text)

    def test_orchestrator_wires_prompt_builder_and_cache_fields(self):
        text = ORCH_PATH.read_text()
        self.assertIn("build-orchestrator-prompt", text)
        self.assertIn("parse-cli-usage", text)
        self.assertIn("cache_creation_input_tokens", text)
        self.assertIn("cache_read_input_tokens", text)
        self.assertNotIn("# Task: $TITLE", text)


class SessionHookPrefixTest(unittest.TestCase):
    def test_stable_prefix_function_is_byte_stable(self):
        script = f"""
set -u
source "{HOOK_PATH}"
print_prompt_cache_prefix
"""
        first = subprocess.check_output(["bash", "-c", script], text=True)
        second = subprocess.check_output(["bash", "-c", script], text=True)
        self.assertEqual(first, second)
        self.assertIn("prompt-cache-prefix-end", first)
        self.assertNotIn("CASE-", first)
        self.assertNotRegex(first, r"\d{4}-\d{2}-\d{2}T")
        self.assertNotIn("$(", first)
        hook = HOOK_PATH.read_text()
        flush_body = hook[hook.index("flush_session_context()"):]
        self.assertLess(
            flush_body.index("print_prompt_cache_prefix"),
            flush_body.index("${VOLATILE_LINES[@]}"),
        )

    def test_hook_stdout_keeps_per_run_ids_after_the_prefix(self):
        prefix = subprocess.check_output(
            ["bash", "-c", f'source "{HOOK_PATH}"; print_prompt_cache_prefix'],
            text=True,
        )

        def run_in(repo: Path) -> str:
            env = os.environ.copy()
            env["HOME"] = str(repo / "home")
            env["CLAUDE_PROJECT_DIR"] = str(repo)
            env["PATH"] = os.environ["PATH"]
            (repo / "home").mkdir(parents=True, exist_ok=True)
            return subprocess.check_output(
                ["bash", str(HOOK_PATH)],
                cwd=str(repo),
                env=env,
                text=True,
                timeout=30,
            )

        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left"
            right = Path(tmp) / "right"
            for repo, token in ((left, "aaa"), (right, "bbb")):
                repo.mkdir()
                subprocess.check_call(["git", "init", "-q"], cwd=repo)
                subprocess.check_call(["git", "config", "user.email", "t@t.com"], cwd=repo)
                subprocess.check_call(["git", "config", "user.name", "T"], cwd=repo)
                (repo / "file.txt").write_text(token + "\n")
                subprocess.check_call(["git", "add", "file.txt"], cwd=repo)
                subprocess.check_call(["git", "commit", "-q", "-m", token], cwd=repo)
            out_left = run_in(left)
            out_right = run_in(right)
            sha_left = subprocess.check_output(
                ["git", "-C", str(left), "rev-parse", "--short", "HEAD"], text=True
            ).strip()
        self.assertTrue(out_left.startswith(prefix), out_left[:400])
        self.assertTrue(out_right.startswith(prefix), out_right[:400])
        self.assertEqual(out_left[: len(prefix)], out_right[: len(prefix)])
        self.assertNotIn(sha_left, out_left[: len(prefix)])
        self.assertIn(sha_left, out_left[len(prefix) :])


if __name__ == "__main__":
    unittest.main()

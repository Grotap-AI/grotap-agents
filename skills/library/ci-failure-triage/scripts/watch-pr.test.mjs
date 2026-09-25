import test from "node:test";
import assert from "node:assert/strict";
import { assessList, assessOne, laneOf, normalizeCheck } from "./watch-pr.mjs";

test("lanes split pytest shards from vitest", () => {
  assert.equal(laneOf("pytest (shard 3/6)"), "pytest-shard");
  assert.equal(laneOf("frontend vitest"), "vitest");
  assert.equal(laneOf("lint"), "other");
});

test("skipped suite check is not success", () => {
  const check = normalizeCheck({ name: "pytest shard 1", status: "COMPLETED", conclusion: "SKIPPED" });
  assert.equal(check.kind, "skipped");
});

test("clean PR is READY", () => {
  const report = assessOne({
    state: "OPEN",
    isDraft: false,
    mergeable: "MERGEABLE",
    mergeStateStatus: "CLEAN",
    reviewDecision: "APPROVED",
    unresolvedThreads: 0,
    checks: [
      { name: "pytest shard 1", status: "COMPLETED", conclusion: "SUCCESS" },
      { name: "vitest", status: "COMPLETED", conclusion: "SUCCESS" },
    ],
  });
  assert.equal(report.verdict, "READY");
});

test("failing shard waits", () => {
  const report = assessOne({
    state: "OPEN",
    mergeable: "MERGEABLE",
    mergeStateStatus: "UNSTABLE",
    unresolvedThreads: 0,
    checks: [{ name: "pytest shard 5", status: "COMPLETED", conclusion: "FAILURE" }],
  });
  assert.equal(report.verdict, "WAITING");
  assert.equal(report.reason, "failing-checks");
});

test("missing shards are required only when asked", () => {
  const pr = {
    state: "OPEN",
    mergeable: "MERGEABLE",
    mergeStateStatus: "CLEAN",
    unresolvedThreads: 0,
    checks: [{ name: "vitest", status: "COMPLETED", conclusion: "SUCCESS" }],
  };
  assert.equal(assessOne(pr).verdict, "READY");
  const required = assessOne(pr, { requirePytestShards: 6 });
  assert.equal(required.verdict, "WAITING");
  assert.ok(required.blockers.includes("pytest-shards-missing"));
});

test("stack advance and complete", () => {
  const open = { state: "OPEN", mergeable: "MERGEABLE", mergeStateStatus: "CLEAN", unresolvedThreads: 0, checks: [] };
  const advance = assessList([{ number: 1, state: "MERGED" }, { ...open, number: 2 }]);
  assert.equal(advance.verdict, "ADVANCE");
  assert.equal(advance.next, 2);
  const done = assessList([{ number: 1, state: "MERGED" }, { number: 2, state: "MERGED" }]);
  assert.equal(done.verdict, "COMPLETE");
});

#!/usr/bin/env node
/**
 * Origin: pstack v0.15.5 skills/poteto-mode/scripts/watch-pr
 * (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack
 * Port for Grotap: Node and gh, one snapshot by default, six pytest shards
 * and vitest. No bun, no Graphite, no alternate forge.
 *
 * Verdicts: READY, WAITING, ADVANCE, COMPLETE.
 */
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export function laneOf(name) {
  const n = String(name || "").toLowerCase();
  if (n.includes("vitest") || n.includes("frontend")) return "vitest";
  if (n.includes("pytest") || n.includes("shard")) return "pytest-shard";
  return "other";
}

export function normalizeCheck(raw) {
  const name = raw.name || raw.context || "unknown";
  const status = String(raw.status || "").toUpperCase();
  const conclusion = String(raw.conclusion || raw.state || "").toUpperCase();
  let kind = "pending";
  const token = conclusion || status;
  if (token === "SKIPPED" || status === "SKIPPED") kind = "skipped";
  else if (["SUCCESS", "NEUTRAL"].includes(token)) kind = "success";
  else if (["FAILURE", "CANCELLED", "TIMED_OUT", "ERROR", "STARTUP_FAILURE"].includes(token)) kind = "failed";
  else if (status === "COMPLETED" && ["SUCCESS", "NEUTRAL"].includes(conclusion)) kind = "success";
  else if (status === "COMPLETED" && conclusion === "SKIPPED") kind = "skipped";
  else if (status === "COMPLETED" && conclusion) kind = "failed";
  return { name, kind, lane: laneOf(name), status, conclusion };
}

export function assessOne(pr, opts = {}) {
  const checks = (pr.checks || []).map(normalizeCheck);
  const blockers = [];
  if (pr.state === "MERGED") {
    return { verdict: "MERGED", reason: "merged", blockers, checks };
  }
  if (pr.state === "CLOSED") blockers.push("closed-without-merge");
  if (pr.isDraft) blockers.push("draft-pr");
  const mergeable = String(pr.mergeable || "").toUpperCase();
  const mergeState = String(pr.mergeStateStatus || "").toUpperCase();
  if (mergeable === "CONFLICTING" || mergeState === "DIRTY" || mergeState === "CONFLICTING") {
    blockers.push("merge-conflicts");
  }
  if (mergeState === "BEHIND") blockers.push("behind-base");
  if (String(pr.reviewDecision || "").toUpperCase() === "CHANGES_REQUESTED") {
    blockers.push("changes-requested");
  }
  if ((pr.unresolvedThreads || 0) > 0) blockers.push("review-threads");
  if (pr.threadsUnknown) blockers.push("threads-unknown");
  const failed = checks.filter((c) => c.kind === "failed");
  const pending = checks.filter((c) => c.kind === "pending");
  const skippedSuites = checks.filter((c) => c.kind === "skipped" && c.lane !== "other");
  if (failed.length) blockers.push("failing-checks");
  if (pending.length) blockers.push("checks-pending");
  if (skippedSuites.length) blockers.push("suite-skipped");
  const pytest = checks.filter((c) => c.lane === "pytest-shard");
  const vitest = checks.filter((c) => c.lane === "vitest");
  const needShards = Number(opts.requirePytestShards || 0);
  if (needShards && pytest.length < needShards) blockers.push("pytest-shards-missing");
  if (opts.requireVitest && vitest.length === 0) blockers.push("vitest-missing");
  const queueish = checks.some((c) => c.kind === "pending" && c.name.toLowerCase().includes("merge queue"));
  if (pr.inMergeQueue || queueish) blockers.push("merge-queue");

  let verdict = "READY";
  let reason = "merge-ready";
  const hard = blockers.filter((b) => b !== "checks-pending" && b !== "merge-queue");
  if (blockers.includes("merge-queue") && hard.length === 0) {
    verdict = "WAITING";
    reason = "merge-queue";
  } else if (blockers.length) {
    verdict = "WAITING";
    reason = blockers[0];
  }
  return {
    verdict,
    reason,
    blockers,
    checks,
    lanes: {
      pytestShards: pytest,
      vitest,
      other: checks.filter((c) => c.lane === "other"),
    },
  };
}

export function assessList(prs, opts = {}) {
  if (!prs.length) return { verdict: "WAITING", reason: "no-prs", prs: [] };
  if (prs.every((pr) => pr.state === "MERGED")) {
    return { verdict: "COMPLETE", reason: "queue-merged", prs: prs.map((pr) => pr.number) };
  }
  const idx = prs.findIndex((pr) => pr.state !== "MERGED");
  if (idx > 0) {
    return {
      verdict: "ADVANCE",
      reason: "frontier-merged",
      merged: prs.slice(0, idx).map((pr) => pr.number),
      next: prs[idx].number,
    };
  }
  const one = assessOne(prs[0], opts);
  return { ...one, number: prs[0].number, url: prs[0].url || null };
}

function runGh(args) {
  const result = spawnSync("gh", args, { encoding: "utf8" });
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "gh failed").trim();
    const error = new Error(detail);
    error.code = result.status;
    throw error;
  }
  return result.stdout;
}

function repoSlug() {
  const raw = runGh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).trim();
  const [owner, name] = raw.split("/");
  if (!owner || !name) throw new Error(`cannot parse repo from ${raw}`);
  return { owner, name };
}

function unresolvedThreads(owner, name, number) {
  const query = `query($owner:String!,$name:String!,$number:Int!){
    repository(owner:$owner,name:$name){
      pullRequest(number:$number){
        reviewThreads(first:100){ pageInfo { hasNextPage } nodes { isResolved } }
      }
    }
  }`;
  try {
    const stdout = runGh([
      "api", "graphql",
      "-f", `query=${query}`,
      "-f", `owner=${owner}`,
      "-f", `name=${name}`,
      "-F", `number=${number}`,
    ]);
    const data = JSON.parse(stdout);
    const threads = data.data.repository.pullRequest.reviewThreads;
    const unresolved = threads.nodes.filter((node) => !node.isResolved).length;
    return { unresolved, unknown: Boolean(threads.pageInfo.hasNextPage) };
  } catch {
    return { unresolved: 0, unknown: true };
  }
}

export function snapshotFromView(view, threadInfo) {
  const rollup = Array.isArray(view.statusCheckRollup) ? view.statusCheckRollup : [];
  return {
    number: view.number,
    url: view.url,
    title: view.title,
    state: view.state,
    isDraft: Boolean(view.isDraft),
    mergeable: view.mergeable,
    mergeStateStatus: view.mergeStateStatus,
    reviewDecision: view.reviewDecision,
    checks: rollup,
    unresolvedThreads: threadInfo.unresolved,
    threadsUnknown: threadInfo.unknown,
  };
}

function loadLive(number, slug) {
  const view = JSON.parse(runGh([
    "pr", "view", String(number),
    "--json", "number,url,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup",
  ]));
  const threads = unresolvedThreads(slug.owner, slug.name, number);
  return snapshotFromView(view, threads);
}

function parseArgs(argv) {
  const opts = {
    pretty: false,
    statusOnly: false,
    watch: false,
    interval: 30,
    maxPolls: 10,
    stack: [],
    requirePytestShards: 0,
    requireVitest: false,
    fixture: "",
    pr: "",
  };
  const args = [...argv];
  while (args.length) {
    const arg = args.shift();
    if (arg === "--pretty") opts.pretty = true;
    else if (arg === "--status-only") opts.statusOnly = true;
    else if (arg === "--watch") opts.watch = true;
    else if (arg === "--require-vitest") opts.requireVitest = true;
    else if (arg === "--interval") opts.interval = Number(args.shift() || 30);
    else if (arg === "--max-polls") opts.maxPolls = Number(args.shift() || 10);
    else if (arg === "--require-pytest-shards") opts.requirePytestShards = Number(args.shift() || 0);
    else if (arg === "--stack") opts.stack = String(args.shift() || "").split(",").map((s) => s.trim()).filter(Boolean);
    else if (arg === "--from-fixture") opts.fixture = String(args.shift() || "");
    else if (arg === "--help" || arg === "-h") opts.help = true;
    else if (!arg.startsWith("--") && !opts.pr) opts.pr = arg;
    else throw new Error(`unknown arg ${arg}`);
  }
  return opts;
}

function renderPretty(report) {
  const lines = [
    `verdict: ${report.verdict}`,
    `reason: ${report.reason || ""}`,
  ];
  if (report.number) lines.push(`pr: ${report.number}`);
  if (report.next) lines.push(`next: ${report.next}`);
  if (report.lanes) {
    const fmt = (rows) => rows.map((row) => `${row.name}=${row.kind}`).join(", ") || "(none)";
    lines.push(`pytest_shards: ${fmt(report.lanes.pytestShards)}`);
    lines.push(`vitest: ${fmt(report.lanes.vitest)}`);
  }
  if (report.blockers) lines.push(`blockers: ${report.blockers.join(", ") || "(none)"}`);
  return lines.join("\n");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function once(opts) {
  let prs;
  if (opts.fixture) {
    const data = JSON.parse(readFileSync(opts.fixture, "utf8"));
    prs = data.prs;
  } else {
    const numbers = opts.stack.length ? opts.stack : [opts.pr];
    if (!numbers[0]) throw new Error("pass a PR number or --stack bottom,next");
    const slug = repoSlug();
    prs = numbers.map((number) => loadLive(number, slug));
  }
  const report = assessList(prs, opts);
  report.mode = opts.stack.length ? "stack" : "single";
  return report;
}

export async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    process.stdout.write("usage: watch-pr.mjs [--pretty] [--status-only] [--watch] [--stack a,b] [--require-pytest-shards 6] [--require-vitest] <pr>\n");
    return 0;
  }
  const polls = opts.watch && !opts.statusOnly ? opts.maxPolls : 1;
  let report = null;
  for (let i = 0; i < polls; i += 1) {
    report = await once(opts);
    const terminal = report.verdict === "READY" || report.verdict === "COMPLETE" || report.verdict === "ADVANCE";
    const queueStop = report.verdict === "WAITING" && report.reason === "merge-queue";
    if (terminal || queueStop || i === polls - 1) break;
    await sleep(opts.interval * 1000);
  }
  const text = opts.pretty ? `${renderPretty(report)}\n` : `${JSON.stringify(report, null, 2)}\n`;
  process.stdout.write(text);
  return report.verdict === "READY" || report.verdict === "COMPLETE" || report.verdict === "ADVANCE" ? 0 : 1;
}

const invokedDirectly = process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) {
  main(process.argv.slice(2)).then(
    (code) => { process.exitCode = code; },
    (error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 2;
    },
  );
}

---
name: release-and-rollback
description: "Use to land a verified change or roll it back. An independent verdict comes before merge. Railway and Vercel rollback, staging first. Invoke explicitly as release-and-rollback."
disable-model-invocation: true
---

Origin: pstack v0.15.5 shipping playbook (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack — the rollback section is written for Grotap. Graphite and the Origin forge are omitted.

# Release and rollback

CI green is not a verdict. An approving bot is not a verdict. A verdict is an independent pass on the real surface from a team that did not write the change.

Run on the team the task names. Keep that team's model. Do not switch models from this skill. Do not merge, deploy, or roll back production unless the task explicitly says to.

## Land

1. Resolve the forge as `gh`. For each PR, a different team runs `verify-and-prove` against the parent and the head. The result is `PASS`, `PASS+NOTES`, or `FAIL`, posted on that PR.
2. Walk up from the lowest unmerged PR. Stop at the first one without `PASS` or `PASS+NOTES`. A verified PR above an unverified one does not land. Report the ceiling.
3. Record the verdict head SHA, base SHA, and `git patch-id` of the base-to-head diff. Before landing, recompute the patch-id. If it changed, re-verify. Matching commit messages or an older green check do not carry the verdict. After a rebase, rerun mergeability and CI at the current head even when the patch-id matches.
4. Prepare only the bottom PR. Fetch `origin/master`. Rebase onto that tip only when the task allows a rebase. Pushing that rebased branch is a force-push: use `git push --force-with-lease` only, and only on your own PR branch. Never force-push `master`, `main`, or any other shared branch. Then retarget with `gh pr edit <pr> --base master`. Re-check the patch-id. Leave descendants alone.
5. Land one PR at a time, and only when the task says to land. Before merging, check whether this PR must keep a merge commit. That includes a PR that updates `agents/BOOTSTRAP_SHA`, and any PR that says a merge commit is required, such as a grotap-agents pin PR like #7. Squash breaks the host pin chain. Those PRs use a merge commit:

```bash
gh pr merge <pr> --merge
```

If the task says merge-when-ready and checks are still running, `gh pr merge <pr> --merge --auto` on that one PR.

Every other PR stays a squash:

```bash
gh pr merge <pr> --squash
```

If the task says merge-when-ready and checks are still running, `gh pr merge <pr> --squash --auto` on that one PR. Wait until it has merged before preparing the next. `autoMergeRequest` on one PR does not mean the stack is ready.

6. After each merge, fetch trunk, confirm the SHA, drop that PR from the list, and inspect the new bottom PR. Do not assume the host retargeted the child.

The four-reviewer gate (build, logic, security, perf) is outside this folder. Do not merge while it is still required and unsigned.

## Rollback

Staging first. Production only after the task says so, and after you have named the last known-good id.

Frontend is Vercel. API is Railway. Database changes use `db-migrations` and are not undone by a host rollback. If the bad deploy included a contract migration, stop and follow that skill's forward-fix. Do not drop tables from this skill.

### Staging

1. List current production and staging deployments. Record the bad id and the previous good id.
2. Roll the staging frontend back to the previous Vercel deployment (`vercel rollback <deployment>` on the staging project, or the project's documented equivalent). Confirm the staging URL serves the previous build.
3. Roll the staging API back by redeploying the previous successful Railway deployment id. Do not `railway up` the broken tree. If the CLI on the box cannot target a deployment id, redeploy that id from the Railway dashboard and record the id. Do not guess a flag.
4. Run `verify-and-prove` on staging against the restored build. Inconclusive is not a restored service.

### Production

Pause. When the task allows it, repeat the staging steps on the production Vercel project and the production Railway service. Watch health after the rollback. Report both ids, the commands, and the proof.

Reply with the verified run and its ceiling, each verdict and which team produced it, what landed, and, for a rollback, the ids and the staging proof.

# Forge Push-Mirror Procedure — inverting the mirror direction for one repository

**Status: READ-ONLY PREPARATION.** Nothing in this document has been executed. No mirror, repository,
webhook, token, branch or setting was created, deleted or modified on Forgejo or GitHub to produce it.
Every claim below is either a direct API/tool result captured on 2026-09-16, a quote from Forgejo's own
documentation/API schema, or is explicitly flagged as inferred. This is a procedure to be run later,
not a change log of work already done.

**Scope.** Mechanism (A), owner-approved 2026-09-15 (`forgejo-cutover-gate.md`): `forge.grotap.com`
becomes the push path, Forgejo **push-mirrors** to GitHub, Railway and Vercel keep building from GitHub
untouched. This document covers inverting the mirror direction for exactly one repository, the
designated canary `grotap-platform-docs`.

---

## 0. Prerequisites — who needs which headers (read this before running anything below)

Cloudflare Access was enabled in front of `forge.grotap.com` during the preparation of this document
(by a separate concurrent session). This changes what every command below needs, depending on where it
runs from:

| Caller | Extra headers needed | Why |
|---|---|---|
| **Workstation, any `https://forge.grotap.com/api/v1/...` call** | `CF-Access-Client-Id`, `CF-Access-Client-Secret` (Doppler `FORGE_CF_ACCESS_CLIENT_ID` / `FORGE_CF_ACCESS_CLIENT_SECRET`), **plus** a real `User-Agent` (a bare urllib/curl-default UA gets a Cloudflare 403/1010), **plus** `Authorization: token $FORGE_API_TOKEN` | Without the two `CF-Access-*` headers the call gets a `302` to `grotap.cloudflareaccess.com`, not a `403` or a JSON error — that 302 is easy to misread as a broken token. Verified live: `GET /api/v1/version` returns `{"version":"13.0.5+gitea-1.22.0"}` with the headers, a `302`/HTML login page without them. |
| **A fleet box (agent-02..06) or forge-01 itself, HTTPS to the forge** | None extra | A Bypass policy admits the five worker IPv4/IPv6 addresses and forge-01 on **every path**, not only `/api/actions` — this covers runner clone/checkout traffic (`/Grotap-AI/<repo>`, `git-upload-pack`) as well as the runner protocol. Confirm this is still true before relying on it; it is an edge policy someone else can change. |
| **Any caller, git-over-SSH** | None — SSH is unaffected regardless of caller | `forge-ssh.grotap.com:2222` is an **unproxied** DNS record. Cloudflare's proxy cannot carry the SSH transport, so Access — which only sits at Cloudflare's edge — never sees this traffic. It is protected solely by the Hetzner firewall `forge-fw` and Forgejo's own SSH key auth. |

This document's own command blocks were run from the workstation and include the two `CF-Access-*`
headers throughout. If a fleet box runs the same commands later, those two headers are harmless but
unnecessary.

---

## 1. Can a Forgejo repo be a pull mirror and a push mirror at the same time?

**Short answer: not usefully, and there is exactly one supported, irreversible API path to change it.**

**What was checked, live, against `forge.grotap.com` (Forgejo 13.0.5+gitea-1.22.0):**

- `GET /api/v1/repos/Grotap-AI/grotap-platform-docs` returns `"mirror": true`, `"mirror_interval":
  "10m0s"`, `"permissions":{"admin":true,"push":true,"pull":true}`. The `push` permission bit being
  `true` does **not** mean a git push will succeed and stick — see the second point below.
- `GET /api/v1/repos/Grotap-AI/grotap-platform-docs/push_mirrors` returns `[]`, same as all four repos
  (`grotap-platform`, `grotap-agents`, `grotap-landing`, `grotap-platform-docs`) — confirming the
  finding already on record in `forgejo-cutover-gate.md`.
- The `EditRepoOption` schema (used by `PATCH /repos/{owner}/{repo}`, read from the live
  `/swagger.v1.json`) has **no `mirror` boolean field at all.** It exposes `mirror_interval` (the pull
  schedule's own cadence) and `enable_prune`, but nothing to flip `is_mirror` off. The generic repo-edit
  endpoint cannot do this conversion.
- The live swagger **does** expose a dedicated endpoint for exactly this: `POST
  /repos/{owner}/{repo}/convert` — `"summary": "Convert a mirror repo to a normal repo."`,
  `operationId: repoConvert`, **no request body**, response `200` returns the updated `Repository`
  object, `403`/`404`/`422` otherwise. This was added in Forgejo PR #8932 ("feat: Allow converting
  mirror repos to normal through the API"), merged 2026-09-14 (per that PR's own metadata) into the
  `v13.0.0` milestone — so it ships in the 13.0.5 this instance runs. The PR's own discussion describes
  the conversion as **"a one-time and one-way operation"** — there is no corresponding
  "convert-back-to-mirror" endpoint, and none is planned as of this writing.

**Why the two modes cannot coexist in practice, not just in the schema.** Even setting the API aside:
Forgejo's pull-mirror scheduler force-syncs a mirrored repo's branches to match the upstream (GitHub)
on every `mirror_interval` cycle — 10 minutes here. If a push mirror were somehow attached to a repo
that is *still* an active pull mirror, any commit that landed on the Forgejo side between pull cycles
would be silently overwritten by the next scheduled pull-sync before a push mirror ever got a chance to
relay it to GitHub. The pull direction has to stop before the push direction can mean anything. That is
exactly what `/convert` does: it clears `is_mirror` and removes the repository's row from the internal
`mirror` table (the same table `forgejo-cutover-gate.md` already queries directly —
`select repo_id, datetime(updated_unix,'unixepoch'), datetime(next_update_unix,'unixepoch') from
mirror;` — a disappeared row for this `repo_id` is the direct proof the schedule stopped).

**What is lost, and what is not.** The PR discussion documents this only as "one-time, one-way," not in
terms of specific data. Based on the endpoint's shape (no request body, no destructive-sounding response
fields, a metadata-only operation is the natural reading of "flip `is_mirror` false and drop the mirror
row") the git objects, refs, issues, wiki and webhooks of the repository are expected to be untouched —
**this is an inference, flagged as such**, because Codeberg's own anti-scraper page blocked a direct read
of the Go implementation diff during this research (its `pulls/8932/files` page returns deliberately
garbled content to automated fetchers, with an explicit "if you are an AI scraper... stop visiting"
notice). What is unambiguously and permanently lost is the **pull-mirror relationship itself** — you
cannot use the API to turn `grotap-platform-docs` back into a repo that auto-fetches from GitHub. Re-
establishing that would mean deleting the repository and re-migrating it as a fresh pull mirror (a new
`id`, and everything keyed to the old one — issues, PR history, webhook config, org visibility settings
— would need to be recreated, not carried over). Given this migration's entire point is to stop pulling
from GitHub and start pushing to it, this loss is the intended end state, not a side effect to guard
against — but it does mean **step 2 below (the conversion) is the point of no return in this procedure,
not the push-mirror creation that follows it.**

---

## 2. Exact semantics of a Forgejo push mirror — the most important question in this task

**Confirmed: yes, it is destructive by design, in both directions, and there is a real safeguard.**

Forgejo's own documentation (`forgejo.org/docs/v15.0/user/repo-mirror/`, the push-mirror section) states
in so many words:

> "This will force push to the remote repository. This will overwrite any changes in the remote
> repository!"

and separately, on the exact git invocation:

> When no branch filter is specified, Forgejo uses `git push --mirror`. With a branch filter, only
> matching branches are pushed.

`git push --mirror` is git's own most dangerous push mode — not a Forgejo-specific extension of it. Per
git's own `git-push(1)` manual, `--mirror` pushes **all** refs (branches, tags, `refs/remotes/`,
`refs/notes/`, everything under `refs/`) unconditionally and force-overwrites them, **and it deletes any
ref on the remote that does not exist locally.** That second half is the sharp edge: an unfiltered push
mirror pointed at a GitHub repo that has *any* branch or tag Forgejo doesn't know about will delete that
branch or tag on GitHub the first time it syncs — not just overwrite divergent history on refs both
sides share.

**The documented safeguard is the `branch_filter` field on `CreatePushMirrorOption`** (confirmed present
in the live swagger schema, alongside `remote_address`, `remote_username`, `remote_password`, `use_ssh`,
`sync_on_commit`, `interval`). Per the docs quote above, supplying a filter switches Forgejo away from
the bare `--mirror` invocation to pushing (and, implicitly, only touching) the matching branch names —
glob patterns like `feature/*` are supported. **Never create a push mirror with an empty branch filter
against a repository GitHub still needs intact.** For this canary, set `branch_filter: master`
explicitly, even though — see the pre-check below — there is currently nothing else on either side to
lose.

**Pre-check performed for the canary, live, 2026-09-16:**

```
GitHub grotap-platform-docs — all heads and tags:
  88812af393be7b3b7317adcb995a86e3e8f39e5f  refs/heads/master
  (no tags)

Forge grotap-platform-docs — all branches:
  master
  (no tags)

Head parity: 88812af393be7b3b7317adcb995a86e3e8f39e5f on both sides — MATCH.
```

This repository has exactly one ref on either side, and they are identical right now. That is precisely
why it was chosen as the canary: there is nothing an unfiltered `--mirror` push could delete even if the
filter were skipped by mistake. **This will not be true for `grotap-platform`** (§6) — re-run this same
ref inventory there before ever repeating this procedure on it, because that repository has multiple
branches and the deletion risk is real.

---

## 3. GitHub token and scopes

The Doppler `GITHUB_TOKEN` (`grotap`/`prd`) is a **fine-grained personal access token** (`github_pat_…`
prefix), belonging to the GitHub user `Grotap1` (id `264898885`).

**Checked live, without printing the token:**

- `curl -sI -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user` → `200 OK`. The
  response headers carry **no `X-OAuth-Scopes` header at all.** This is expected and not a failure —
  that header is a classic-PAT artifact; fine-grained tokens don't emit it, so "check the scopes header"
  as originally framed doesn't apply to this token type. Scopes have to be inferred from what specific
  endpoints allow or refuse.
- `GET /repos/Grotap-AI/grotap-platform-docs` and `GET /repos/Grotap-AI/grotap-platform`, both, report
  `"permissions":{"admin":true,"maintain":true,"push":true,"triage":true,"pull":true}` for this token's
  principal. **The token can push to both repositories.**
- It is **not** a full-admin grant in the fine-grained sense: `GET
  /repos/Grotap-AI/grotap-platform-docs/branches/master/protection` and the same call against
  `grotap-platform` both return `403` (this token lacks the "Administration" fine-grained repository
  permission needed to read classic branch-protection settings). `GET /orgs/Grotap-AI/rulesets` returns
  `403 {"message":"Resource not accessible by personal access token"}` — it also cannot enumerate
  org-level rulesets. See §4 for why that specific gap matters here.

**No push was attempted** — that would not be read-only. §5's procedure treats the controlled test
commit as the actual proof this token can write to `grotap-platform-docs` under whatever rule regime
applies to it.

---

## 4. Branch protection / rulesets on GitHub

**`grotap-platform-docs`:**
- `GET .../branches/master/protection` → `403` (token lacks visibility, not necessarily proof of no
  protection — see above).
- `GET .../rulesets` → `200 []`.
- `GET .../rules/branches/master` (the lower-privilege "effective rules that apply to this branch"
  endpoint — needs only read access, not admin) → `200 []`. **No repository-level ruleset is visible to
  this token on this repo.**

**`grotap-platform`:**
- Same three checks return the same shapes: `403` on classic protection, `200 []` on repo rulesets,
  `200 []` on effective rules for `master`.

**The org-level check is what actually explains the "Bypassed rule violations" message the task
description names.** `GET /orgs/Grotap-AI/rulesets` → `403 {"message":"Resource not accessible by
personal access token"}`. Put together with the two `200 []` results above, the picture is: **whatever
is enforcing "Changes must be made through a pull request" on `grotap-platform`'s `master` is configured
at the GitHub **organization** level, not the repository level** — repo-level rulesets and effective
branch rules both read empty, so an org ruleset (most plausibly one targeting a repo-name pattern such
as "all repositories" or a wildcard) is the only thing left that fits, and this token cannot enumerate
org rulesets to confirm its exact target pattern or its bypass-actor list.

**What this means for the mirror.** The "Bypassed" wording in the push output the task describes is
GitHub's own audit-log language for "a rule matched, and the pushing actor is on that rule's bypass
list, so the push was allowed anyway." Because a push mirror authenticates to GitHub with whatever
credential you give it — Forgejo has no separate GitHub identity, it just runs `git push` as configured
— **a push mirror built with this same `GITHUB_TOKEN` will bypass the identical rule, on the identical
terms, as any other push made with this token today.** Whether that rule's target pattern actually
covers `grotap-platform-docs` cannot be confirmed from outside the org-rulesets view this token doesn't
have. The honest way to find out without guessing is the live test in §5 step 6: if the rule applies
here too, the sync response / `hook_task` / push output will carry the same "Bypassed rule violations"
line seen on `grotap-platform`; if it doesn't apply, the push simply succeeds with no such line. Either
outcome is fine operationally (the token can push either way) — this is flagged here because **routing
every automated commit around a "PRs only" rule is a decision worth being explicit and owner-visible
about**, not something to let surface for the first time as an unremarked log line once `grotap-platform`
itself is on this path (§6).

---

## 5. The procedure

All commands assume the workstation, Git Bash, `doppler run -p grotap -c prd --` for secrets, and the
two `CF-Access-Client-*` headers per §0. Every step states what it changes, what is lost if it's
destructive, and how to undo it.

### Step 1 — Pre-checks (read-only, repeat immediately before step 3)

```bash
doppler run -p grotap -c prd -- bash -c '
UA="User-Agent: grotap-cutover/1.0"
AUTH="Authorization: token $FORGE_API_TOKEN"
CFID="CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID"
CFSEC="CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET"

echo "-- forge head --"
curl -s -H "$AUTH" -H "$CFID" -H "$CFSEC" -H "$UA" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs/branches/master" \
  | grep -o "\"id\":\"[a-f0-9]*\"" | head -1

echo "-- github head --"
git ls-remote https://github.com/Grotap-AI/grotap-platform-docs.git refs/heads/master

echo "-- full ref inventory, both sides (must match before proceeding) --"
git ls-remote --heads --tags https://github.com/Grotap-AI/grotap-platform-docs.git
curl -s -H "$AUTH" -H "$CFID" -H "$CFSEC" -H "$UA" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs/branches" | grep -o "\"name\":\"[^\"]*\""
'
```

**Pass condition:** the two head SHAs are identical, and the two ref lists are identical (as they were
at last check: one ref, `master`, matching on both sides). If they differ, stop — do not proceed to
step 3 until you understand why, using the same divergence-diagnosis approach `forgejo-cutover-gate.md`
item 1 already documents (`docker logs forgejo | grep SyncMirrors`).

### Step 2 — Take a backup before the irreversible step

The forge already has a working backup mechanism (`forgejo-cutover-gate.md` item 6): `forgejo dump`
into `/opt/forge/backups`, uploaded to the dedicated Wasabi bucket via the `forge-backup` scoped key.
Trigger one manually and confirm the object lands, rather than trusting the nightly timer alone for a
change you are about to make by hand:

```bash
ssh forge-01 'docker exec -u git forgejo forgejo dump --file /backups/pre-push-mirror-$(date -u +%Y%m%dT%H%M%SZ).zip'
```

Confirm the resulting object appears in the Wasabi bucket (per the gate doc's own upload verification
pattern) before step 3. This is not a substitute for the standing nightly backup — it is a point-in-time
safety net for this specific change.

### Step 3 — Convert the repo from pull-mirror to normal (IRREVERSIBLE — read §1 again first)

```bash
doppler run -p grotap -c prd -- curl -s -X POST \
  -H "Authorization: token $FORGE_API_TOKEN" \
  -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \
  -H "User-Agent: grotap-cutover/1.0" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs/convert"
```

**What this changes:** `is_mirror` flips to `false`; the repository's row in Forgejo's internal `mirror`
table is removed, which stops the 10-minute pull-from-GitHub schedule permanently. Verify both:

```bash
# repo object should now show "mirror": false and no "mirror_interval"
doppler run -p grotap -c prd -- curl -s -H "Authorization: token $FORGE_API_TOKEN" \
  -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \
  -H "User-Agent: grotap-cutover/1.0" "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs" \
  | grep -o '"mirror":[a-z]*'

# the mirror table row for this repo should be gone
ssh forge-01 "docker exec -u git forgejo sqlite3 /data/gitea/gitea.db \
  \"select * from mirror where repo_id = (select id from repository where name='grotap-platform-docs');\""
```

**What is lost:** the automatic GitHub → Forgejo pull relationship for this repo, permanently, by
design (§1). Repository content, issues, wiki, and webhook configuration are expected to be untouched
(inferred, not directly source-verified — see §1's caveat).

**Rollback:** there is no API to reverse this. Recovery, if needed, is: delete the (now-normal)
`grotap-platform-docs` repository on the forge, and re-migrate it fresh as a pull mirror from GitHub
(`POST /repos/migrate` with the mirror flag), which gets a new internal `id` and starts with no
issues/PR history/webhooks — because none of those existed to carry over on this repo in the first
place (its `has_issues`/etc. were the mirror defaults), this rollback is low-cost specifically *for this
canary*. It would not be low-cost for a repo with real issue/PR/webhook history — see §6.

### Step 4 — Configure the push mirror

```bash
doppler run -p grotap -c prd -- bash -c '
curl -s -X POST \
  -H "Authorization: token $FORGE_API_TOKEN" \
  -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \
  -H "User-Agent: grotap-cutover/1.0" \
  -H "Content-Type: application/json" \
  -d "{
    \"remote_address\": \"https://github.com/Grotap-AI/grotap-platform-docs.git\",
    \"remote_username\": \"x-access-token\",
    \"remote_password\": \"$GITHUB_TOKEN\",
    \"branch_filter\": \"master\",
    \"interval\": \"10m0s\",
    \"sync_on_commit\": true
  }" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs/push_mirrors"
'
```

**What this changes:** creates one row in Forgejo's push-mirror config for this repo. Nothing is pushed
to GitHub yet by this call alone (creation only). `branch_filter: master` is set deliberately per §2 —
do not leave it blank, even though the ref inventory in step 1 shows nothing else exists to delete right
now.

**Verify the config, without ever printing the stored credential** (Forgejo does not return
`remote_password` in the API response — confirmed from the `PushMirror` response schema, which has
`remote_address`, `remote_name`, `interval`, `last_error`, `last_update`, `public_key`, `sync_on_commit`,
but no password field):

```bash
doppler run -p grotap -c prd -- curl -s -H "Authorization: token $FORGE_API_TOKEN" \
  -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \
  -H "User-Agent: grotap-cutover/1.0" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs/push_mirrors"
```

**Rollback (safe, reversible):**

```bash
doppler run -p grotap -c prd -- curl -s -X DELETE \
  -H "Authorization: token $FORGE_API_TOKEN" \
  -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \
  -H "User-Agent: grotap-cutover/1.0" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs/push_mirrors/github.com"
```
(the mirror's `remote_name`, needed for the delete path, is read from the GET above — Forgejo names it
after the remote host by default.) Deleting the push-mirror config does not touch anything it already
pushed; GitHub keeps whatever commits were synced.

### Step 5 — Force a sync

```bash
doppler run -p grotap -c prd -- curl -s -X POST \
  -H "Authorization: token $FORGE_API_TOKEN" \
  -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \
  -H "User-Agent: grotap-cutover/1.0" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/grotap-platform-docs/push_mirrors-sync"
```

At this point, since heads already match (step 1), this sync should be a no-op push (nothing new to
send) — which is itself a useful first proof that the mirror doesn't misbehave on an idle repo before
it is ever asked to move real content.

### Step 6 — Make a real commit on the forge and prove it reaches GitHub

This is the step that actually tests the reversed direction, not just the wiring:

```bash
# push a trivial commit to the forge over SSH (unaffected by CF Access — see §0)
git clone ssh://git@forge-ssh.grotap.com:2222/Grotap-AI/grotap-platform-docs.git /tmp/docs-canary-test
cd /tmp/docs-canary-test
echo "push-mirror canary test $(date -u +%FT%TZ)" >> PUSH_MIRROR_CANARY.md
git add PUSH_MIRROR_CANARY.md
git commit -m "test: push-mirror canary — safe to revert"
git push origin master
```

Then, within the mirror's `interval` (10 minutes, or immediately if you re-run step 5's sync call):

```bash
git ls-remote https://github.com/Grotap-AI/grotap-platform-docs.git refs/heads/master
```

**Pass:** the SHA on GitHub matches the new commit just pushed to the forge. **Also check** whether the
push carried a "Bypassed rule violations" line (via `git push -v` output, or `GET
.../push_mirrors/github.com`'s `last_error` field, or the forge container log) — per §4, that line
appearing or not appearing is itself the answer to whether the org-level rule extends to this repo.

**Rollback for this test:** revert the test commit on the forge (`git revert`, then push again — the
mirror carries the revert out the same way) rather than force-pushing over it, so the mirror's own
`--mirror`/filtered-force behavior is never exercised on a real content conflict as its first real job.

---

## 6. What must be true before doing the same to `grotap-platform`

Per `forgejo-cutover-gate.md`'s existing canary-first sequencing, moving `grotap-platform`'s **push
path** (this document's procedure) is gated on the canary being **boring for 14 consecutive days**:
daily parity checks that never diverge, at least 20 green Actions runs on the forge runners with zero
infrastructure-caused failures, no unplanned forge restart, and at least one in-window backup
restored and verified. None of that clock has started yet — this document is preparation, not day one.

Beyond that existing gate, three things specific to `grotap-platform` change the risk profile from what
was just exercised on the canary:

- **It has real content to lose.** Unlike `grotap-platform-docs` (one ref, `master`, nothing else), run
  the exact same `git ls-remote --heads --tags` / forge-branches comparison from step 1 against
  `grotap-platform` before ever repeating this procedure there, and expect it to show multiple branches
  and possibly tags. `branch_filter` must be set to cover every branch genuinely in use, or an
  under-scoped filter will silently strand branches nobody is pushing to the forge, while an unfiltered
  mirror risks deleting exactly the branches a filter was meant to protect. This is not a copy-paste of
  step 4's `"branch_filter": "master"`.
- **It is what Railway builds from.** `forgejo-cutover-gate.md`'s deploy-source table records
  `grotap-backend`, `grotap-ingestion-worker` and `grotap-agent-worker` on a **native GitHub webhook
  trigger** watching `master` — mechanism (A) is specifically chosen so this stays untouched, but that
  makes GitHub's copy of `master` operationally load-bearing in a way `grotap-platform-docs`'s never
  was. A mis-scoped or accidentally unfiltered push-mirror sync here does not just lose a doc history —
  it can break production deploys within the same mirror cycle that broke the ref.
- **The org-level rule bypass (§4) is not a maybe here — it is already happening.** The task's own
  framing states pushes to `grotap-platform` master today already log "Bypassed rule violations ...
  Changes must be made through a pull request." Wiring an unattended, scheduled push mirror through the
  same bypassed rule is a materially different thing from a human or an agent doing it interactively —
  it should be an explicit owner sign-off at the point `grotap-platform` is converted, not something
  that is only ever discovered in a log line after the fact.

Two items already tracked as **hard blockers** in `forgejo-cutover-gate.md` (items 6 and 7) are not
specific to the push-mirror direction, but should not be considered separately resolved by the time
`grotap-platform` reaches this procedure: the nightly backup timer has never yet completed an
**unattended** run (wiring is proven, but every successful upload to date was hand-triggered), and the
shared fleet SSH key has not been retired (per that document, Phase 2c is the critical-path piece and
retirement is still blocked on an orchestrator deploy). Neither blocks the canary work in this document,
but both should read clean before `grotap-platform`'s push path moves, since that is the point at which
a forge outage or a credential compromise stops being "some CI experiments" and starts being the
platform's own source of truth.

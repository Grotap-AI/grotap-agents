# Forge Push-Mirror Procedure — inverting the mirror direction for one repository

**Status: EXECUTED ON THE CANARY, 2026-09-17. This is no longer a plan.** Owner approved the canary
cutover that day; §5 steps 1-6 were run end to end against `grotap-platform-docs` and **only** that
repository. `grotap-platform`, `grotap-agents` and `grotap-landing` were not touched and remain
GitHub -> Forgejo pull mirrors. The irreversible conversion in step 3 has happened: the canary is a
normal repository on the forge and can never again auto-pull from GitHub through the API.
See §7 for the execution record, the corrections it forced on this document, and the window clock.

The body below (§0-§6) is preserved as written on 2026-09-16, because it is what was reviewed and
approved. Where execution contradicted it, §7 says so explicitly rather than editing the claim away.
Every claim in §0-§6 is either a direct API/tool result captured on 2026-09-16, a quote from Forgejo's
own documentation/API schema, or is explicitly flagged as inferred.

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

> **CORRECTION, measured 2026-09-16 — do not plan the round-trip test around SSH.** Git over SSH to
> the forge is indeed untouched by Cloudflare Access, but it **does not currently work**: no user SSH
> key is registered on the Forgejo account, so `forge-ssh.grotap.com:2222` refuses the connection.
> "Access cannot see it" and "it works" are different claims and this document previously conflated
> them. Either register a key on the Forgejo account first, or do the round-trip over HTTPS using the
> header form below.
>
> **Git over HTTPS to the forge needs the Access headers too, and fails SILENTLY without them.**
> A `git push` without them reports success and lands nothing — proven by a canary push that never
> arrived while the command exited 0. Pass them explicitly:
>
> ```bash
> git -c http.extraHeader="CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" >     -c http.extraHeader="CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" >     push origin master
> ```
>
> The same silent-success trap applies to `curl -sf` against the forge API: **`-f` fails on 4xx/5xx
> only, not on the 302** that Access returns, so curl exits 0 with empty output and any `json.load`
> pipe downstream sees nothing. A check written that way stops checking without appearing to.

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
# NOTE — read the SSH caveat below before running this. As of 2026-09-16 this clone FAILS.
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

---

## 7. Execution record — canary inverted 2026-09-17

Owner approved the canary cutover on 2026-09-17. §5 steps 1-6 were executed against
`grotap-platform-docs` and no other repository. All timestamps UTC, all values read back from the
live APIs or the forge's own SQLite database.

### 7.1 Blocker cleared first — the workstation IP had rotated off two allow lists

`GET /api/v1/version` from the workstation returned a Cloudflare **403 WAF block page** (`CF-RAY
a3c8dec95eae1421-SEA`), not the 302-to-Access-login §0 describes — with *and* without the Access
headers, so it was not an Access problem at all. The WAF sits in front of Access and was refusing the
request before Access ever saw it.

Cause: the workstation's public IPv4 is now **98.97.42.231**; both allow lists still carried the
previous lease **98.97.42.234**. `98.97.42.231/32` was added to each, and nothing else was changed:

- Zone WAF ruleset `833d63affc5d44be931d2ce74bf8f9fd` (`forge-access-lock`), rule
  `52f22e14dedb4990b5d5779d42046117` — ruleset version 2 -> 3 at `2026-09-17T14:42:00Z`. The six
  fleet/forge IPv4 addresses and six IPv6 `/64` prefixes are unchanged.
- Hetzner firewall `forge-fw` (id `11628446`) — the same `/32` added to the three rules that carried
  the workstation: `tcp/22`, `icmp`, `tcp/2222`. The Cloudflare-only `tcp/80` and `tcp/443` rules were
  not touched. Without this, `ssh forge-01` also timed out, so step 2's backup was unreachable.

**Verification after the change:** `/api/v1/version` returns `{"version":"13.0.5+gitea-1.22.0"}` with
the token + both `CF-Access-*` headers + a real User-Agent, and **302** without the Access headers —
exactly the behaviour §0 documents. `ssh forge-01` connects.

**Left as-is deliberately, flag for cleanup:** the stale `98.97.42.234/32` was **not** removed from
either list. It is a dynamic residential address that may now belong to somebody else on the same ISP.
Removing it is a separate, narrow change; it was not made here because the brief was to add the current
IP without widening or otherwise editing the policy.

### 7.2 Pre-state captured before the irreversible step (step 1)

| Fact | Value at 2026-09-17T14:42Z |
|---|---|
| `push_mirrors` on all four repos | `[]` — unchanged from 2026-09-16 |
| Canary repo `id` | `4` |
| `mirror` / `mirror_interval` | `true` / `10m0s` |
| `original_url` | `https://github.com/Grotap-AI/grotap-platform-docs.git` |
| `private` / `default_branch` | `true` / `master` |
| `has_issues` / `has_wiki` / `has_pull_requests` / `has_actions` | `true` / `true` / `false` / `false` |
| Forge refs | one branch `master` @ `88812af393be7b3b7317adcb995a86e3e8f39e5f`, **no tags** |
| GitHub refs | `88812af393be7b3b7317adcb995a86e3e8f39e5f refs/heads/master`, nothing else |
| Head parity | MATCH |
| `mirror` table row (repo_id 4) | `interval=600000000000` (10m in ns), `enable_prune=1`, `lfs_enabled=0`, `remote_address=https://github.com/Grotap-AI/grotap-platform-docs.git` |
| Repo git config | `remote.origin.mirror=true`, `remote.origin.tagopt=--no-tags`, `remote.origin.fetch=+refs/*:refs/*` and `+refs/tags/*:refs/tags/*`, credential embedded in `remote.origin.url` |

That table is the rebuild-by-hand record: everything needed to re-migrate this repo as a fresh pull
mirror if the rollback in step 3 ever has to be taken.

### 7.3 Backup taken (step 2)

Run via the existing `/usr/local/bin/forge-backup.sh` rather than a bare `forgejo dump`, because that
script also verifies the archive's contents and re-reads the uploaded object to compare sizes:

```
2026-09-17T14:44:08Z OK ts=20260917T144404Z key=forge-01/2026/09/forge-20260917T144404Z.zip size=178301763 elapsed=4s local_kept=2
```

**Correction to `forgejo-cutover-gate.md` item 6:** that document records that the nightly backup timer
had never completed an **unattended** run. It has now — `forge-backup.timer` fired on its own at
`2026-09-16T04:26:35Z` (143,068,543 B) and `2026-09-17T04:20:10Z` (174,289,387 B), both logged `OK`
with a verified upload, next scheduled `2026-09-18T04:21:25Z`. The remaining half of item 6 — a restore
performed from an **in-window** backup — is still outstanding and is part of the 14-day gate.

### 7.4 The irreversible conversion (step 3)

`POST /api/v1/repos/Grotap-AI/grotap-platform-docs/convert` -> **HTTP 200** at
**`2026-09-17T14:44:40Z`**. Read back immediately:

- Repo object: `"mirror": false`, `"mirror_interval": ""`. `original_url`, `default_branch`, `private`,
  `has_issues`, `has_wiki` all unchanged — the §1 inference that the conversion is metadata-only held
  for every field this repo actually had.
- `select * from mirror;` now returns **three** rows — `grotap-platform`, `grotap-agents`,
  `grotap-landing`. The `repo_id = 4` row is gone. That is the direct proof the 10-minute pull schedule
  stopped for the canary, and that the other three were untouched.
- Re-verified by API: the other three still read `"mirror": true, "mirror_interval": "10m0s"` and
  `push_mirrors == []`.

### 7.5 Push mirror created and synced (steps 4-5)

Created at `2026-09-17T14:44:59Z` with `branch_filter: master`, `interval: 10m0s`,
`sync_on_commit: true`, `remote_username: x-access-token`, password = Doppler `GITHUB_TOKEN`.

> **CORRECTION to §4's rollback command.** Forgejo did **not** name the remote after the host. The
> assigned `remote_name` is **`remote_mirror_MMfyFXpzGq`**, a generated identifier. The delete path is
> therefore `.../push_mirrors/remote_mirror_MMfyFXpzGq`, not `.../push_mirrors/github.com`. Always read
> `remote_name` from the GET before constructing a DELETE.

Forced sync at `2026-09-17T14:45:08Z` -> HTTP 200, `last_error: ""` — the intended no-op push against
an already-matching head.

### 7.6 Round trip proven (step 6) — over HTTPS, not SSH

`GET /api/v1/user/keys` still returns `[]`, so §0's SSH correction still stands and the test was done
over HTTPS with the credential in the URL plus both Access headers set as `http.extraHeader`:

1. Cloned the canary from `https://forge.grotap.com/Grotap-AI/grotap-platform-docs.git`.
2. Appended a line to `PUSH_MIRROR_CANARY.md`, committed, pushed to the **forge**:
   `88812af..9f470be  master -> master`.
3. Forge API re-read: `master = 9f470be51d046fa6d309ae1c1ebd5076f17a7ffb` — the push **stuck**, which
   is the thing a pull mirror would have silently reverted within ten minutes.
4. `sync_on_commit` fired by itself; push-mirror `last_update` = `2026-09-17T14:45:35Z`,
   `last_error: ""`.
5. GitHub `refs/heads/master` = `9f470be51d046fa6d309ae1c1ebd5076f17a7ffb` by `14:45:44Z` — **under 30
   seconds end to end, with no manual sync call.**
6. A fresh clone **from GitHub** carries 3 commits, 80 files, and the canary line intact — GitHub still
   holds a complete, current copy, which is the standing rollback condition.

**On the "Bypassed rule violations" question in §4:** it did not arise here.
`GET /repos/Grotap-AI/grotap-platform-docs/rules/branches/master` returns `200 []`, the mirror's
`last_error` is empty, and the forge log shows no rule text. So this canary says **nothing** about
whether the org-level "changes must be made through a pull request" rule covers `grotap-platform`.
§6's requirement for an explicit owner sign-off at that point is unchanged and unanswered.

### 7.7 Direction is now asymmetric — the new standing hazard

Until today a mistake on the forge was erased within ten minutes by the pull sync. That safety net is
gone for this repo, and the asymmetry is the opposite of what people's habits expect:

- **forge -> GitHub:** automatic, on every commit, within seconds.
- **GitHub -> forge:** **does not happen at all any more.** Nothing pulls.

So a commit pushed **directly to GitHub** on `grotap-platform-docs` will not reach the forge, and the
next push-mirror sync will **force it out of existence on GitHub** — the mirror pushes the forge's
`master` over it. That force-overwrite path has deliberately **not** been exercised; it is an inference
from the `--mirror`/branch-filter semantics in §2, and it should stay unexercised. Treat
`forge.grotap.com` as the only place this repository is written.

### 7.8 The 14-day boring window

**Window start: `2026-09-17T14:44:40Z`** (the moment of conversion). **Earliest close:
`2026-10-01T14:44:40Z`**, and only if all four criteria below read clean.

| Criterion (from `forgejo-cutover-gate.md`) | Measured against |
|---|---|
| Parity check ran daily, never diverged | forge `master` SHA == GitHub `master` SHA for `grotap-platform-docs`, once per day, 14 days |
| **20 Actions runs completed green**, zero infrastructure-caused failures | Baseline at window start: `select count(*) from action_run` = **4**, `max(id)` = **4**, latest `created` = `2026-09-16 04:23:53`, all four `status=1` (success). The criterion is **20 runs with `id > 4`** created inside the window at `status=1`. A failing test is acceptable; a runner that cannot fetch a task is not. All five runners (`agent-02`..`agent-06`) were online at window start. **These runs must be produced deliberately — the canary repo has `has_actions=false` and carries no workflows, so ambient traffic will produce zero of them.** |
| No unplanned forge restart | `forgejo` container was `Up 45 hours` at window start; `caddy` `Up 46 hours` |
| One in-window backup restored and verified | No restore has been performed inside the window yet. `forge-20260917T144404Z.zip` is the first in-window artifact available to restore from |

Only after that window closes clean does `grotap-platform` move, and then in the two steps §6
describes — push path first, deploy trigger later.

### 7.9 What still hardcodes GitHub in the fleet path (survey only, nothing edited)

Confirmed against `origin/master` of both repositories on 2026-09-17. **`agents/` ownership splits per
file, not per repo** — `dispatch.sh` and `dispatch-poller.sh` live only in `grotap-platform`, while
`orchestrator-run.sh` and `review-gate-cron.sh` exist in **both** repos as two separate live copies
that must be changed together. The line numbers in `forgejo-cutover-gate.md` have drifted; current
values:

**`grotap-platform` @ origin/master**

| File | Lines | What it does |
|---|---|---|
| `agents/dispatch.sh` | 450, 785, 1169 | `git clone https://github.com/Grotap-AI/grotap-agents.git` — bootstrap, three copies in three heredoc'd blocks (gate doc said 328/613/945) |
| `agents/run-task.sh` | 53 | same bootstrap clone — **not listed in the gate doc** |
| `agents/scripts/orchestrator-run.sh` | 334 (code), 78 + 393 (rotation instructions in comments/stderr) | bootstrap clone of `grotap-agents` (gate doc said 224) |
| `agents/scripts/review-gate-cron.sh` | 311 | clones `grotap-platform` (gate doc said 291) |
| `agents/scripts/dispatch-poller.sh` | 19, 31-32, 49, 85 | **GitHub REST Contents API** — `GITHUB_TOKEN` from Doppler (19), `AGENTS_REPO`/`TASK_PATH` constants (31-32), two `PUT`/read calls to `api.github.com/repos/.../contents/...` (49, 85). Line numbers still exact. Needs a Forgejo Contents-API equivalent, not a hostname swap |
| `agents/watchdog.sh` | 48 | `api.github.com/repos/${GITHUB_REPO}/commits?sha=...` freshness probe — **not listed in the gate doc** |
| `agents/setup-server.sh` | 9, 48, 54 | `REPO_URL`, the `x-access-token` clone and a `git remote set-url` back to GitHub — **not listed in the gate doc** |

**`grotap-agents` @ origin/master** (the second copies)

| File | Lines | What it does |
|---|---|---|
| `agents/scripts/orchestrator-run.sh` | 361 | clones **`grotap-platform`** — note this copy differs from the `grotap-platform` copy, which clones `grotap-agents` |
| `agents/scripts/review-gate-cron.sh` | 249 | clones `grotap-platform` |
| `agents/scripts/deploy-execute.sh` | 34 | clones `grotap-platform` — **not listed in the gate doc** |

Adjacent, outside the fleet run path but same dependency: `scripts/monitoring/deploy_freshness_watchdog.py:71`,
`scripts/backup/semimonthly-source.sh:72`, `scripts/claudecode/seed-secrets.sh:87`,
`scripts/verify_github_pat_scope.py:32` (all `grotap-platform`).

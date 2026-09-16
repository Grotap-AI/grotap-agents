# Forgejo Cutover Gate — go/no-go before the source of truth moves

*Written 2026-09-15. Owner-approved. This is the checklist that must pass, in full, before anyone
points a push path or a deploy trigger at `forge.grotap.com` instead of GitHub. Every item is
written as a command with a threshold, because a gate nobody can run is not a gate.*

## Status — what is live, and what is emphatically not cut over

`forge-01` (Hetzner cpx21, Ashburn, `178.156.246.81`) runs **Forgejo 13.0.5** behind Caddy in a
docker compose stack at `/opt/forge`, served at `https://forge.grotap.com` (Cloudflare-proxied) with
git-over-SSH on `forge-ssh.grotap.com:2222` (deliberately unproxied — Cloudflare cannot proxy the
SSH protocol). All four repositories — `grotap-platform`, `grotap-agents`, `grotap-landing` and
`grotap-platform-docs` — exist on the forge under the `Grotap-AI` organization as **pull mirrors**
refreshing every ten minutes. CI is real: `forgejo-runner` v13.1.0 runs on agent-02 through agent-06
in host-execution mode as an unprivileged `forge-runner` user, and a signed webhook receiver
(`POST /api/v1/forgejo/pipeline-sync`) is live in production.

**GitHub is still the source of truth and nothing has been cut over.** Mirroring runs in exactly one
direction, GitHub → Forgejo. Railway and Vercel both still build from GitHub. Every human and every
agent still pushes to GitHub. Today a total forge outage costs us some CI experiments and nothing
else, which is precisely the property cutover gives up. Treat "the forge is up and mirroring" as a
statement about the forge, never as a statement about the migration.

Commands below run from the workstation in Git Bash. Secrets come from Doppler (`grotap` / `prd`)
and are never typed inline.

> **EVERY forge HTTPS command in this document needs two extra headers as of 2026-09-16.**
> Cloudflare **Access is now live** in front of `forge.grotap.com`. A call from the workstation
> without them gets a **302 to `grotap.cloudflareaccess.com`**, not an application error — so it
> looks like a broken token or a dead API, and it is neither.
>
> ```
> -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID"
> -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET"
> ```
>
> Both live in Doppler `grotap` prd and dev, so they arrive through the `doppler run` wrapper the
> commands already use. A forge call therefore now needs **three** things: a real `User-Agent`
> (a bare `urllib` UA is refused with 403 / error 1010), `Authorization: token $FORGE_API_TOKEN`,
> and the two Access headers. The commands below are written without the Access headers; **add them
> to every `curl` that targets `$FORGE_URL`.**
>
> **Two paths are deliberately exempt and must not have the headers added:**
> - **Git over SSH on `forge-ssh.grotap.com:2222`** — unproxied; Access cannot cover the SSH protocol.
> - **Anything originating on a fleet box or forge-01** — a Bypass policy covers the six fleet/forge
>   IPv4 addresses and all six IPv6 /64s on every path, which is what keeps runner clone and checkout
>   traffic working (`/Grotap-AI/<repo>` and `git-upload-pack`, not merely `/api/actions`).
>
> The WAF ruleset still sits underneath Access as a second layer, and both `CLOUDFLARE_API_TOKEN` and
> `CLOUDFLARE_EDGE_TOKEN` are now a live account-owned token (`grotap-edge-20260916`) with Zone WAF
> write on `grotap.com` — so an emergency IPv6 /64 addition is an API call again rather than a
> dashboard trip. Team domain: `grotap.cloudflareaccess.com`.

## Gate run of record — 2026-09-15, 23:20-23:34 UTC

The full eight-item gate was executed read-only on 2026-09-15. Result at the time of the run: **NO-GO** — two hard
blockers failing and two further items not clean. **Item 6 has since passed** (2026-09-16 04:26Z, see
below) and item 8's edge control has since been resolved by enabling Cloudflare Access. Item 7 remains
the outstanding hard blocker, and the canary-first sequencing below has not started.

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Mirror head parity | **PASS** | Two readings 14 min apart, identical both times: `grotap-platform@master 87de93cd1`, `grotap-agents@master 716ef6196`, `grotap-landing@main 27938f0ec`, `grotap-platform-docs@master 88812af39`. No divergence. |
| 2 | Mirror freshness / stuck check | **PARTIAL** | `mirror_updated` lag 18 min (under threshold). But the first sqlite read showed `next_update_unix` ~9 min in the PAST for all four repos — the documented stuck signature — and the second read 10 min later showed it caught up. Item 1 never diverged across that window, so it reads as scheduler jitter, not a dead mirror. Not a clean pass. |
| 3 | Canary Actions run | **PASS** | Run 3 `success`, created 2026-09-15T18:20:24Z, head_sha `cbf4848b1`, within the 24 h window. |
| 4 | Runner fleet | **PASS** | Five `action_runner` rows, all 1-2 s stale; all five hosts `active`; ceilings exact — agent-02..05 `CPUQuotaPerSecUSec=2s` / `MemoryMax=2147483648`, agent-06 `3s` / `4294967296`. |
| 5 | Webhook HMAC | **PASS** | `signed 202`, `tampered 401 {"detail":"Invalid signature"}`, `health 200 {"ok":true,"configured":true}`. |
| 6 | Backup | **PASS** (2026-09-16 04:26Z) | Unattended timer fire: `OK forge-01/2026/09/forge-20260916T042632Z.zip size=143068543`, 3 s, exit 0, no human in the loop. See below. |
| 7 | Shared fleet key retired | **FAIL — hard blocker** | Shared pubkey still present in `authorized_keys` on all six hosts (counts 2/2/2/2/2/1, none zero); private key still on agent-06 (2 copies) and agent-04 (1). `health-monitor.sh:64` and `SERVERS.md:92` still name it; three `fleet key` prose rows remain at SERVERS.md 78/81/82. |
| 8 | Edge control | **PARTIAL** | Workstation curl returns 200, the expected pre-Zero-Trust allow-list state. Zero Trust could NOT be verified: see the token finding below. |

### Two findings from this run that change earlier entries in this document

**The backup credential is now wrong rather than merely absent.** `/root/.forge-backup.env` still
holds the placeholder and `forge-backup.service` failed three times on 2026-09-15 (18:09:37,
18:20:33, 18:20:35, exit 1), with `LAST`/`PASSED` both empty — **not one recorded success, ever**.
The bucket `grotap-forge-backups` (region `us-west-1`) holds exactly one object,
`forge-01/2026/09/forge-20260915T180937Z.zip`, 141,327,757 bytes, owned by the Wasabi **root**
account — that is the restore drill's presigned-URL upload, not a timer-fired backup.

**A correction to an earlier reading of this run, kept because the trap is reusable.** This audit
reported that the `WASABI_FORGE_*` pair in Doppler had changed from a placeholder into a real-looking
key that failed `InvalidAccessKeyId`. That was **wrong**. Both values were read directly from prd and
dev afterwards: lengths 37 and 41, prefix `REPLACE_ME_`, byte-identical to the reading two hours
earlier. Nothing had changed. `InvalidAccessKeyId` is simply what Wasabi returns when handed
`REPLACE_ME_...` as an access key id — the audit's placeholder check tested for the bare literal
`REPLACE_ME` and so misread a placeholder as a live credential. **Gate the check with
`startswith("REPLACE_ME")`**, which is what `forge-backup-upload.py` itself uses. The underlying
warning still stands on its own merits: a syntactically valid but wrong key is worse than a
placeholder, because the placeholder check is what makes the nightly fail loudly and self-describingly
instead of with a generic S3 error. Verify any populated key with a real `HeadBucket` before
declaring item 6 unblocked.

**Both Cloudflare API tokens in Doppler are invalid.** `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_EDGE_TOKEN` each fail `GET /user/tokens/verify` with
`{"success":false,"errors":[{"code":1000,"message":"Invalid API Token"}]}`. This is **not** the
`access.api.error.not_enabled` signal recorded earlier in this document — that reading was taken when
the tokens still worked. The practical consequence is that **the WAF ruleset
`833d63affc5d44be931d2ce74bf8f9fd` is currently the only edge control and cannot be inspected or
modified by API.** If the allow list ever needs an emergency change — adding a box, or restoring
fleet access after an IPv6 change — it is a dashboard action until a token is reissued. Fix the token
before relying on item 8 either way.

## Cloudflare Access — read this before running any check below

Zero Trust was enabled on `forge.grotap.com` on 2026-09-16. **Every forge HTTP call now needs a
Cloudflare Access service token in addition to the Forgejo API token**, and a call that omits it does
not fail cleanly — it is answered with a **302 to the Access login page**. Measured:

```
Authorization: token $FORGE_API_TOKEN                          -> 302
  + CF-Access-Client-Id + CF-Access-Client-Secret              -> 200 {"version":"13.0.5+gitea-1.22.0"}
```

`curl -sf` does **not** fail on a 302 — `-f` covers 4xx/5xx only — so curl exits 0, emits nothing, and
the pipe into `python -c json.load` sees empty stdin. The check then errors out or quietly counts
nothing. **An unauthenticated forge check looks like "no data", not like "denied".** That is the same
failure family this document was written to catch, so it is called out here rather than left to be
rediscovered.

The service token is in Doppler prd as `FORGE_CF_ACCESS_CLIENT_ID` / `FORGE_CF_ACCESS_CLIENT_SECRET`;
every command below already carries both.

**`git` over HTTPS needs them too**, and fails even more quietly — `git push -q` to the forge without
them reports nothing and lands nothing, because the redirect is swallowed. Working form:

```bash
doppler run -p grotap -c prd -- bash -c 'git   -c http.extraHeader="CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID"   -c http.extraHeader="CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET"   ls-remote origin master'
```

**git over SSH is not a fallback today.** `ssh://git@forge-ssh.grotap.com:2222` returns "make sure you
have the correct access rights" — no user SSH key is registered on the Forgejo account. That record is
unproxied and Access does not touch it, so it *could* be the Access-immune path, but only once a public
key is uploaded to the forge user. Until then HTTPS + service token is the only way in.

## Go / no-go checklist

### 1. Mirror head parity — the primary signal

Compare each mirror's default-branch head on the forge against the same ref on GitHub. This beats an
elapsed-time check outright: a mirror that has silently stopped fetching still advances its
`mirror_updated` timestamp on every scheduled attempt, so it looks fresh while serving a stale tree.
A divergent head cannot hide that way.

```bash
doppler run -p grotap -c prd -- bash -c '
for R in grotap-platform grotap-agents grotap-landing grotap-platform-docs; do
  META=$(curl -sf -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" \n       -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \n       -H "Authorization: token $FORGE_API_TOKEN" "$FORGE_URL/api/v1/repos/Grotap-AI/$R")
  BR=$(printf "%s" "$META" | python -c "import sys,json;print(json.load(sys.stdin)[\"default_branch\"])")
  FG=$(curl -sf -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" \n       -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \n       -H "Authorization: token $FORGE_API_TOKEN" "$FORGE_URL/api/v1/repos/Grotap-AI/$R/branches/$BR" \
       | python -c "import sys,json;print(json.load(sys.stdin)[\"commit\"][\"id\"])")
  GH=$(git ls-remote "https://github.com/Grotap-AI/$R.git" "refs/heads/$BR" | cut -f1)
  if [ "$GH" = "$FG" ]; then echo "OK       $R@$BR ${FG:0:9}"
  else echo "DIVERGED $R@$BR github=${GH:0:9} forge=${FG:0:9}"; fi
done'
```

Read the default branch from the API rather than assuming `master` — `grotap-landing` uses `main`.

**Pass:** all four lines read `OK`, on two consecutive runs taken at least one mirror cycle (ten
minutes) apart. The two-reading rule exists so that a push landing seconds before the check is not
mistaken for a stalled mirror; a genuine stall stays divergent across the cycle boundary.

The last verified clean parity, each repository against its **own** default branch, was at 18:19Z on
2026-09-15 and all four equalled GitHub at that moment:

| Repository | Default branch | Head |
|---|---|---|
| `grotap-platform` | `master` | `87de93cd1` |
| `grotap-agents` | `master` | `63473efd1` |
| `grotap-landing` | `main` | `27938f0ec` |
| `grotap-platform-docs` | `master` | `88812af39` |

(An earlier draft of this document recorded `616311770` as the last clean parity on
`grotap-platform`. It was not: that is the SHA the mirror was **stuck at** while failing to fetch.
Do not resurrect it as a reference point.)

**On any `DIVERGED` result, the required next step is the mirror log.** Parity tells you the mirror
is broken; it does not tell you why, and the freshness timestamp in item 2 will actively mislead you.
Read the cause straight from the container:

```bash
ssh forge-01 'docker logs forgejo 2>&1 | grep -E "SyncMirrors.*failed|could not read Password"'
```

The worked example is the real incident line from 2026-09-15:

```
SyncMirrors [repo: Grotap-AI/grotap-platform]: failed to update mirror repository: fatal: could not read Password for 'https://sanitized-credential@github.com': terminal prompts disabled
```

### 2. Mirror freshness — secondary staleness signal only

```bash
doppler run -p grotap -c prd -- bash -c '
for R in grotap-platform grotap-agents grotap-landing grotap-platform-docs; do
  curl -sf -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" \n       -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \n       -H "Authorization: token $FORGE_API_TOKEN" "$FORGE_URL/api/v1/repos/Grotap-AI/$R" \
  | python -c "import sys,json,datetime as d;r=json.load(sys.stdin);t=d.datetime.strptime(r[\"mirror_updated\"],\"%Y-%m-%dT%H:%M:%SZ\");print(r[\"name\"], int((d.datetime.utcnow()-t).total_seconds()//60), \"min\")"
done'
```

**Pass:** every repository under **20 minutes**. The cadence is ten minutes and a lag of about eight
was observed at the last probe, so twenty is two missed cycles — tight enough to notice a dead
scheduler, loose enough not to fire on one slow fetch. It never substitutes for item 1.

**This signal is worse than weak — it is actively false, and there is an incident to prove it.** On
2026-09-15 three of the four mirrors could not authenticate to GitHub at all: the migrate API had
stored the token as the URL's *username* with no password, so every pull prompted for a password and
died. `grotap-agents` kept working only because it is a public repository and needs no credential;
the other two merely happened to show matching heads because nothing had been pushed upstream since
migration. Forgejo advanced `updated_unix` on every **failed** cycle: at **18:14:48Z** the container
logged three `SyncMirrors ... failed ... could not read Password` lines, one per broken repository,
and at that identical second `mirror_updated` read `2026-09-15T18:14:48Z` for **all four**
repositories — including the three that had just failed. A failed fetch and a fresh timestamp, the
same second.

(The three repos were fixed around 18:17–18:19 by repointing them at the platform's `GITHUB_TOKEN`.
If you probe now and see `18:19:16Z`/`18:19:17Z`, that is the forced re-sync that followed the fix —
all four healthy at that point, which is also where item 1's 18:19Z parity table comes from. Do not
mistake those readings for incident evidence; the incident reading is 18:14:48.)

So the rule is not the softer "freshness can only demote confidence." It is that **a completely dead
mirror reports fresh, and can go on reporting fresh for days.** This incident is recorded here so
that nobody later re-promotes freshness to a primary signal. A green reading in this item means
nothing on its own; only item 1 decides.

**A cheaper tell, and one that doesn't lie the way `mirror_updated` does:** check `next_update_unix`
against `now()` directly. At 18:14:48 the three broken repos had `next_update_unix` sitting in the
past — `16:42:00`–`16:42:05`, frozen since their last successful cycle — while the healthy public
repo showed `18:24:48`, correctly scheduled ten minutes forward. A mirror whose `next_update_unix` is behind `now()` is **overdue**, which is necessary but not
sufficient evidence of a stall. Measured 2026-09-16: three repos read `next_update_unix` ~10
minutes in the past with zero sync failures in the log, then synced normally on the next pass —
the scheduler was simply late, not broken. **Stuck means the value does not advance across two
readings a full interval apart, or the log carries a `SyncMirrors ... failed` line.** One overdue
reading on its own is jitter; treating it as a fault produces the opposite error to the one this
check exists to prevent.

```sql
SELECT repo_id, datetime(updated_unix,'unixepoch'), datetime(next_update_unix,'unixepoch') FROM mirror;
```

Run this first — it needs no log access and no incident to trigger it. Fall back to the `docker logs`
grep in item 1 only once this shows a stuck row and you need the root cause. The healthy contrast,
read from the box after the fix: all four repos at `18:54:49`–`18:54:50` with `next_update_unix`
`19:04:49`–`19:04:50`, ten minutes ahead as they should be.

### 3. Canary Actions run green on the forge runners

The canary already exists: `Grotap-AI/forge-smoke` on the forge, with `.github/workflows/smoke.yml`
doing a checkout, a `setup-python`, and a host-execution proof. Do not create a second one.

```bash
doppler run -p grotap -c prd -- bash -c 'curl -sf -H "CF-Access-Client-Id: $FORGE_CF_ACCESS_CLIENT_ID" \n       -H "CF-Access-Client-Secret: $FORGE_CF_ACCESS_CLIENT_SECRET" \n       -H "Authorization: token $FORGE_API_TOKEN" \
  "$FORGE_URL/api/v1/repos/Grotap-AI/forge-smoke/actions/tasks?limit=5" \
  | python -c "
import sys,json
for r in json.load(sys.stdin)[\"workflow_runs\"]:
    print(r[\"run_number\"], r[\"status\"], r[\"created_at\"], r[\"head_sha\"][:9])
"'
```

**Pass:** the most recent run is `success` and was created within the last 24 hours. Push an empty
commit to `forge-smoke` to produce a fresh run rather than trusting an old tick. History to date:
run 1 at 16:44:23Z and run 2 at 17:17:35Z on 2026-09-15, both `success` on agent-05, confirming
`runner user: forge-runner`, python 3.12.14 and node v22.22.0; run 3 was also `success`, and is the
run that proved the resource ceilings in item 4.

**A green canary proves the runners work; it does not prove a runner can still fetch** — and a fetch
failure is exactly what the edge change in item 8 risks, since the runners reach the forge through
that same edge. So this item is not satisfied once and for all: **any change to the edge control
invalidates the current green and requires a fresh canary run afterwards**, as item 8 also demands.
A 23-hour-old success taken before an edge change is not evidence about the state after it.

### 4. Runner fleet healthy on all five boxes

There is no admin runner API on this Forgejo build, so read the runner table directly and confirm
the service on each box.

```bash
ssh forge-01 "docker exec -u git forgejo sqlite3 /data/gitea/gitea.db \
  \"select name, strftime('%s','now') - last_online as stale_s from action_runner order by name;\""

for H in agent-02 agent-03 agent-04 agent-05 agent-06; do
  printf '%s ' "$H"
  ssh -o BatchMode=yes "$H" "systemctl is-active forgejo-runner; \
    systemctl show forgejo-runner -p CPUQuotaPerSecUSec -p MemoryMax"
done
```

**Pass:** exactly five rows, one per box, every `stale_s` under **120** seconds; all five hosts
report `active`; **and every host reports its resource ceilings**. Labels are `ubuntu-latest:host` /
`ubuntu-24.04:host`, capacity 2, registered org-wide.

The runner now shares each box with an agent tmux session, so it is bounded rather than trusted. A
load watch showed it had to be, and the drop-in
`/etc/systemd/system/forgejo-runner.service.d/10-resources.conf` was applied to all five boxes:

| Hosts | Settings |
|---|---|
| agent-02, agent-03, agent-04, agent-05 | `CPUQuota=200%` · `MemoryHigh=1600M` · `MemoryMax=2G` |
| agent-06 | `CPUQuota=300%` · `MemoryHigh=3G` · `MemoryMax=4G` |

`systemctl show` must therefore report `CPUQuotaPerSecUSec=2s` and `MemoryMax=2147483648` (2G) on
agent-02..05, and `3s` / `4294967296` (4G) on agent-06. **A runner unit without that drop-in is a
regression, not a variation** — re-apply it and reload before passing this item. The ceilings are not
merely theoretical: a real CI job ran green underneath them (`forge-smoke` run 3, `success`).

Note for anyone reading run history: the agent fleet is hard-stopped by an Anthropic org usage cap
until 2026-10-01 and the assign loop is disabled, so the boxes will look idle for reasons that have
nothing to do with forge load.

### 5. Webhook HMAC verified end to end

```bash
doppler run -p grotap -c prd -- python - <<'PY'
import hashlib, hmac, json, os, urllib.request, urllib.error
UA = "curl/8.5.0"                      # a bare urllib UA is refused by Cloudflare with 403 / 1010
url = "https://api.grotap.com/api/v1/forgejo/pipeline-sync"
body = json.dumps({"ref": "refs/heads/master", "after": "0"*40,
                   "repository": {"id": 1, "name": "grotap-platform",
                                  "full_name": "Grotap-AI/grotap-platform"}}).encode()
good = hmac.new(os.environ["FORGEJO_WEBHOOK_SECRET"].encode(), body, hashlib.sha256).hexdigest()
for label, sig in (("signed", good), ("tampered", "0"*64)):
    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": "application/json", "User-Agent": UA,
        "X-Forgejo-Event": "push", "X-Forgejo-Signature": sig})
    try:
        with urllib.request.urlopen(req, timeout=25) as r: print(label, r.status, r.read().decode())
    except urllib.error.HTTPError as e: print(label, e.code, e.read().decode())
req = urllib.request.Request("https://api.grotap.com/api/v1/forgejo/health", headers={"User-Agent": UA})
with urllib.request.urlopen(req, timeout=20) as h: print("health", h.status, h.read().decode())
PY
```

**Pass:** `signed 202`, `tampered 401`, and `health 200 {"ok":true,"configured":true}`. Then confirm
a real delivery rather than only a synthetic one: push to a mirrored repository and check that
Forgejo's `hook_task` records `is_succeed=1` for the delivery. The implementation is
`backend/app/routers/forgejo.py`, covered by eight tests in
`backend/tests/test_forgejo_webhook.py`; it authenticates with HMAC-SHA256 over the raw request body
keyed by `FORGEJO_WEBHOOK_SECRET` — deliberately not the platform-wide `X-Node-Secret`, because the
forge is a separate trust domain.

**Its limit is part of the gate, not a defect:** the route records pushes and *cannot start an agent
run*. Nothing downstream of cutover may be designed on the assumption that a forge push triggers
work; the assign loop still picks work from `pipeline_cases`.

### 6. Backup restore-proven AND nightly running — HARD BLOCKER

This item has two axes and only one of them is satisfied. **The restore is proven. The nightly is
not running**, and will fail every night until one owner action completes.

The gate was never "a backup job exists" or "an archive appeared in the bucket" — it is that an
archive has been restored and verified. The dump is itself a credential (app.ini `SECRET_KEY` and
`INTERNAL_TOKEN`, the SQLite database with password hashes and API tokens, every repository), so it
belongs in its own Wasabi bucket under a scoped key, never the platform DR bucket.

**Mechanism.** forge-01 now has a dedicated backup volume — host `/opt/forge/backups`, container
`/backups`, owned by `git` at mode 0700 — so `forgejo dump --file /backups/...` writes beside the
previous dump instead of sweeping it into the new archive, which is what happens when the dump
directory sits inside the data directory.

**Restore — DONE and PASSED.** On 2026-09-15 a restore was performed end to end **from Wasabi, not
from a local copy**: object `forge-01/2026/09/forge-20260915T180937Z.zip`, 141,327,757 bytes,
SSE-S3 AES256, sha256 identical to the on-box archive. It was restored into a throwaway container
and verified there:

- `PRAGMA integrity_check` = `ok`, 125 tables present.
- `user` / `repository` row counts 2 / 5, matching live.
- `access_token` / `webhook` / `action_runner` / `mirror` counts 1 / 1 / 5 / 4, matching live.
- `grotap-platform.git` restored with 758 refs and 69,825 in-pack objects;
  `git fsck --no-dangling` exited 0.
- The restored instance booted and served an authenticated API call.

The throwaway was then torn down. That is the dated restore record this item asked for.

**Nightly — NOT running.** A systemd timer `forge-backup.timer` is enabled and active, daily at
04:20 UTC with jitter and `Persistent=true`. It will **fail every night** until an owner action
completes: the scoped Wasabi sub-key it needs could not be created by API, because the Wasabi key in
Doppler is itself a sub-user (`platform-backup-agent`) and both `iam:CreateUser` and
`iam:PutUserPolicy` returned `AccessDenied`. `/root/.forge-backup.env` therefore holds a placeholder,
and the job exits immediately with the self-announcing error
`WASABI_ACCESS_KEY_ID is still the placeholder`. The first upload above was proven using a
short-lived presigned PUT URL minted off-box, so no long-lived credential has ever reached forge-01
— and none should until the scoped key exists.

**Owner action — DONE 2026-09-15 23:5xZ.** The owner signed in to Wasabi root and the console work was
driven from there: customer-managed policy `arn:aws:iam::100000470445:policy/ForgeBackupWrite` and
sub-user `forge-backup` (programmatic access only, no console login, policy attached directly rather
than through a group). The real key pair was verified against the bucket **before** being written to
Doppler prd and dev. Proven with that key: `HeadBucket` OK, `ListObjectsV2` OK,
`CreateMultipartUpload` + `AbortMultipartUpload` OK, `PutObject` + `HeadObject` with SSE AES256 OK,
`DeleteObject` **AccessDenied as designed**, and `platform-backups` / `grotapsourcecode` /
`grotap-dr-backups` all denied. The verification left a 34-byte proof object at
`forge-01/.permission-check-20260915T2352Z.txt` which only the root key can remove — it is not a
nightly success either, so do not count it as one.

**The policy needs five actions, not three.** `s3:PutObject`, `s3:GetObject` and `s3:ListBucket` are
not sufficient: the 141 MB archive crosses boto3's 8 MB multipart threshold, so
`s3:ListMultipartUploadParts` and `s3:AbortMultipartUpload` are both required — the abort path is
what runs when a transfer fails, and without it a failed upload leaves an un-abortable multipart
sitting in the bucket. `s3:DeleteObject` is deliberately excluded: retention pruning runs locally on
forge-01, not in the bucket, so an attacker on that box cannot wipe backup history.

**Wiring completed 2026-09-15 ~23:55Z.** `/root/.forge-backup.env` on forge-01 has been written with
the scoped key pair and the whole path is proven end to end on a real archive. The bucket now reads,
independently re-listed:

| When | Size | Object |
|---|---|---|
| 18:11:11Z | 141,327,757 | `forge-01/2026/09/forge-20260915T180937Z.zip` — root-owned restore-drill artifact |
| 23:53:18Z | 34 | `forge-01/.permission-check-20260915T2352Z.txt` — policy proof object, root-key-deletable only |
| 23:55:12Z | 142,521,928 | `forge-01/2026/09/forge-20260915T235510Z.zip` — **first real upload through the scoped key** (3 s elapsed, `local_kept=2`) |

**PASSED 2026-09-16 04:26:32Z — the timer fired unattended and succeeded:**

```
Sep 16 04:26:32 forge-01 systemd[1]: Starting forge-backup.service...
Sep 16 04:26:35 forge-01 forge-backup.sh[17704]: OK forge-01/2026/09/forge-20260916T042632Z.zip size=143068543
Sep 16 04:26:35 forge-01 systemd[1]: forge-backup.service: Deactivated successfully.
```

Three seconds, 143,068,543 bytes, exit 0, no human in the loop. Next fire 2026-09-17 04:27:14 UTC.
That is the run that counts: the 18:20 attempt on the 15th failed on the placeholder and the 23:55 one
was hand-triggered. **Both axes of this item are now satisfied** — a restore proven from Wasabi onto a
scratch host with `git fsck` clean, and a scheduled archive that runs and uploads on its own.

It also fired while agent-02 and agent-03 were running live agent work with CI runners up on all five
boxes, so the backup window and the fleet's working hours demonstrably overlap without contention.
One data point, not a stress test.

**Do not let this close the wrong thing.** The canary-first sequencing below separately requires that
a backup *taken inside the 14-day boring window* be restored and verified. This archive was taken
before that window starts, so it does not satisfy that clause — and the distinction is the same
"proven once is not proven ongoing" trap that the hand-triggered run already sprang once in this
document.

**Pass:** the restore record above stands (satisfied), **and** the nightly has run unattended and
uploaded on its own schedule at least once — that is, the placeholder is gone and a timer-fired run
appears in the bucket without a human minting a URL for it. Restore-proven alone is not this item.

### 7. Shared fleet SSH key retired — HARD BLOCKER

Per-host keys `~/.ssh/grotap_<host>` now exist for agent-02..06 and forge-01, each proven by a
login, and the workstation `~/.ssh/config` was switched to them (backup `~/.ssh/config.bak-20260915`).
They were installed **alongside** the shared key, which still works everywhere. Deleting the shared
key is what remains, and it is not yet safe: the shared private key lives on agent-06 (both `root`
and `agent`) and agent-04 (`agent`), and **agent-06's deploy, health and DR crons SSH out with it**.
Removing it before those crons move breaks the fleet's own automation. Concretely, the blocker is
this work:

- Move agent-06's deploy / health / DR crons onto per-host keys.
- Fix `agents/scripts/health-monitor.sh`, which still runs
  `ssh -i /home/agent/.ssh/grotap_agents` (currently line 64).
- Update `agents/SERVERS.md`, which still documents the shared key as the root SSH method. It needs
  **two** greps, because the file records the key in two different forms: `grotap_agents` finds the
  literal invocation (one occurrence), and `fleet key` finds the prose rows that say
  `Root SSH = fleet key` (three occurrences — GEX131, maps-01, forge-01). The prose rows are the ones
  a reader must rewrite when the key is retired, and they do not contain the string the first grep
  looks for.
- Only then remove the public key from every `authorized_keys` and delete the private key from
  agent-06 and agent-04.

**Grep for the string, not the line number.** `health-monitor.sh` moved from line 59 to 64 within an
hour, when commit `6bd54b4` fixed that file's roster and added a comment block above the call. An
earlier draft of this section also miscounted `SERVERS.md` as "two hits, lines 82 and 92" — in fact
the literal `grotap_agents` has only ever appeared once (line 92); what sits at 78, 81 and 82 is the
prose `Root SSH = fleet key`. That miscount is exactly why both greps below are required: a check
that looks only for the path silently passes while three rows still tell a reader the fleet key is
the way in. Treat every line number here as a hint that will rot, and the strings as the check:

```bash
grep -rn 'grotap_agents' agents/scripts/health-monitor.sh agents/SERVERS.md
grep -rni 'fleet key' agents/SERVERS.md
```

#### Measured scope of the retirement, 2026-09-15 (this item is much larger than the four bullets above)

A full sweep of every cron, systemd timer and repository reference was run on 2026-09-15. It found
that the four bullets above are a subset, not the whole job, and that **the largest dependency is not
on the fleet boxes at all — it is the production orchestrator on Railway.**

**agent-06 is the only box whose scheduled jobs SSH to other boxes**, and its two most frequent jobs
run under **root's** crontab, not `agent`'s — `health-monitor.sh` and `update-fleet-cli.sh` are
invoked directly as root, while `reconcile_dispatch.py` runs `sudo -u agent`. All three connect as
`root@<target>`. Any key migration therefore has to cover both source users on agent-06, not just
`agent`. agent-04 merely holds the
private key at rest; nothing scheduled on it uses the key. agent-02, agent-03 and agent-05 hold no
private key at all and never originate SSH. agent-04's `root` has no private key either — only
`agent` does. So the cron work is confined to one box, and it is these four jobs:

| Schedule | Job | How it names the key |
|---|---|---|
| `*/5 * * * *` | `health-monitor.sh` | **hardcoded**, no override: `ssh -i /home/agent/.ssh/grotap_agents` |
| `0 6 * * *` | `update-fleet-cli.sh` | cron line re-asserts `SSH_KEY=/home/agent/.ssh/grotap_agents` |
| `*/10 * * * *` | `reconcile_dispatch.py` -> `dispatch.sh` | same explicit `SSH_KEY=` in the cron line |
| weekly (backup chain) | `scripts/backup/weekly-openreplay.sh` | `: "${OR_SSH_KEY:=/home/agent/.ssh/grotap_agents}"` |

**The dependency that decides the whole retirement, and is invisible to a file grep.** Production
fleet work does **not** reach the boxes through `agents/dispatch.sh`. A process-ancestry trace on
agent-02 and agent-03 during live runs shows `claude -p` under `bash orchestrator-run.sh` under a
detached launcher with **PPID 1**, no tmux involved. The runs are started by the orchestrator over
SSH. So the SSH credential that carries production throughput is the **orchestrator's**, and the
crons, the workstation scripts and `dispatch.sh` are all secondary to it.

That means **the shared key cannot be retired until the orchestrator is deployed with per-host key
resolution**, no matter what state the cron and script work is in. Retiring it earlier does not
degrade the fleet, it stops it. Anyone reading the file-grep list below will conclude the opposite,
because the orchestrator contributes only three unremarkable lines to it.

**The blocker the earlier draft missed.** `orchestrator/src/config.ts:20-26` loads **one** key from
Doppler (`SSH_PRIVATE_KEY_B64` / `SSH_PRIVATE_KEY`) and uses it for **every** host in `FLEET_HOSTS`.
That secret *is* the shared farm key, and there is no per-host mechanism and no fallback. Deleting
the shared key without changing this takes production pipeline dispatch down completely — every
`/dispatch` call fails. This must be solved and smoke-tested before any `authorized_keys` is touched.
`orchestrator/src/ssh.ts:3` and `orchestrator/src/config/failure-classes.ts:118` also name the key.

**Nine further hosts have no per-host key at all, and all nine are live.** The per-host keys minted on 2026-09-15 cover only
`agent-02..06` and `forge-01`, and they exist **only on the workstation**. Neither agent-06 nor
agent-04 holds a copy of any of them, and agent-06's own `~/.ssh/config` has no fleet `Host` blocks
— just a GitHub deploy-key block — so its scripts fall through to the hardcoded shared path with no
alternative available. Meanwhile `agent-20`/`21` (Team 2), `agent-30`/`31` (Team 3), `agent-40`/`41`
(Team 4), `GEX131`/`llm-gpu-02`, `maps-01` and `claudecode-01` are reached today only through the
workstation `~/.ssh/config`'s catch-all IP-glob blocks, which route them all at `grotap_agents`.
Retiring the key without minting keys for these nine removes all SSH access to them. A sweep on
2026-09-16 confirmed **all nine are reachable and all nine carry the shared key in `root`'s
`authorized_keys`** — none is decommissioned, so none can be skipped:
`agent-20` 87.99.148.22, `agent-21` 5.161.243.18, `agent-30` 167.233.59.142,
`agent-31` 167.233.194.57, `agent-40` 178.156.219.232, `agent-41` 178.156.220.48,
`GEX131`/`llm-gpu-02` 178.63.124.99, `maps-01` 5.161.107.80, `claudecode-01` 178.156.209.112.

**Thirteen workstation scripts each duplicate the same fallback line** — `agents/dispatch.sh:30`
plus `install-dispatcher.sh:22`, `config.sh:6`, `watchdog.sh:19`, `monitor.sh:3`,
`monitor-loop.sh:7`, `collect-reviews.sh:19`, `review-pipeline.sh:13`, `server-status.sh:7`,
`setup-queue.sh:8`, `update-fleet-cli.sh:16`, `setup-support-runner.sh:23`,
`setup-claude-app-runner.sh:20` — none of which source `config.sh`'s exported `SSH_KEY`. Fix the
default once, centrally, rather than thirteen times. Two more have no override mechanism to inherit:
`agents/status-server.js:14` hardcodes the path in JavaScript, and `health-monitor.sh:64` hardcodes
it in the `-i` flag. `scripts/claudecode/seed-secrets.sh:26` and
`services/clamav-scan/scripts/bootstrap-host.sh:13,17` carry the same default for provisioning paths.

**Cosmetic only, do not let them block the gate:** `backend/app/routers/server_connections.py:179`
and `frontend/src/pages/ServerConnectionsSetupPage.tsx:355` carry `ssh_key_label="grotap_agents"` as
a display string — that admin UI health check is a TCP ping and is not wired to SSH auth at all.
The ~20 remaining hits are historical narrative in docs and case files.

**What breaks the moment the key is deleted with nothing else changed:** production orchestrator
dispatch (total loss), agent-06's 5-minute health monitor, the daily fleet CLI update, the 10-minute
dispatch reconciler, the OpenReplay backup leg, every manual `dispatch.sh` invocation from the
workstation, `status-server.js` on port 7654, and all SSH access to the ten hosts listed above.

#### Phase 1 complete — 2026-09-16 04:01Z, additive only

New ed25519 pairs were generated **on agent-06 itself** (a private key is never transported) for each
of its four SSH targets, for both source users: `/home/agent/.ssh/grotap_from06_agent-0{2,3,4,5}` and
`/root/.ssh/grotap_from06_agent-0{2,3,4,5}`. Public halves were appended to `/root/.ssh/authorized_keys`
and `/home/agent/.ssh/authorized_keys` on agent-02..05, and `Host agent-02..05` blocks with
`IdentitiesOnly yes` were appended to both of agent-06's `~/.ssh/config` files, preserving the existing
`github-reports` deploy-key block. Every file modified was backed up as `*.bak-20260916T040148Z`.

All eight new keys were login-proven (`rc=0`, correct `hostname`/`whoami` as root on each target), and
the shared key was re-proven working from both source users to all four targets afterwards. **Nothing
was removed and sshd was not touched on any host.** The shared key remains live everywhere.

#### Phase 2a complete — 2026-09-16 04:07Z, additive only

All nine remaining hosts now have workstation per-host keys at `~/.ssh/grotap_<host>`, each proven by
a real login, with the shared key re-proven working alongside. Public halves were appended only to
`/root/.ssh/authorized_keys` — **none of the nine has a `/home/agent` account**, which is a genuine
difference from agent-02..06 and matters when reasoning about who can reach what.

The GPU box's key is `grotap_llm-gpu-02`, not `grotap_GEX131`: its actual hostname is `llm-gpu-02`,
and the existing convention tracks hostnames (`agent-02`, `forge-01`) rather than Hetzner product
labels. `GEX131` is the Hetzner label and appears in docs and scripts, but it is not an SSH identity.

One wrinkle to know about before editing `~/.ssh/config` again: six of the nine (`agent-20`, `21`,
`30`, `31`, `40`, `41`) already had named `Host` blocks pointing at `grotap_agents`. Rather than
edit those blocks, a new block with the dedicated key was inserted **directly above** each one, which
wins because OpenSSH takes the first matching value. The old blocks are now shadowed dead code, kept
deliberately under the additive-only rule. They should be deleted in the same change that retires the
shared key — not before, and not left behind after. Verify placement with
`ssh -G <host> | grep -i identityfile`, which lists the winning file first.

Backups: `~/.ssh/config.bak-20260916T040704Z` on the workstation, and
`/root/.ssh/authorized_keys.bak-20260916T040704Z` on each of the nine hosts.

#### Phase 2c complete — 2026-09-16 04:11Z, the critical-path piece

The orchestrator connects as the **`agent`** user (`sshUser: process.env.SSH_USER ?? "agent"`), not
as root, so its credentials are a separate problem from every other strand. Per-host ed25519 keys were
generated for each host in the real `FLEET_HOSTS` — read from Doppler rather than assumed, and it is
exactly `agent-02:5.161.74.39:3, agent-03:5.161.81.193:3, agent-04:178.156.222.220:3,
agent-05:5.161.73.195:3, agent-06:5.78.178.81:2`. Public halves went into
`/home/agent/.ssh/authorized_keys` only (root's file untouched), backed up as
`authorized_keys.bak-20260916T041135Z`. Private halves are in Doppler **prd and dev** as
`SSH_PRIVATE_KEY_AGENT_02_B64` … `SSH_PRIVATE_KEY_AGENT_06_B64`, the names derived from the branch's
own `normalizeHostEnvName` rather than guessed.

Every one was proven by a real `agent@` login before being trusted, and the shared key was re-proven
working alongside. A credential in Doppler that has never been proven against the box is the exact
failure mode this whole exercise exists to remove. Note agent-05's hostname answers as
`grotap-dev-agent`, which is correct and not a mis-target.

**What remains before the shared key can be deleted** is now exactly two deploys and a sweep: merge
and deploy the orchestrator branch, deploy the repointed fleet scripts, then prove every box and
every cron works with the shared key already unused. Both deploys are deliberately held for a quiet
window — the assign loop is back on at `max_inflight=14`.

#### Three findings from an independent sweep that change the retirement plan

A second, independent read-only sweep of both repos and the workstation `~/.ssh/config` on
2026-09-16 turned up three things the earlier survey missed. All three would have produced a green
verification followed by a broken fleet.

**1. A script re-plants the shared private key.** `agents/scripts/setup-agent06.sh` (lines 7-9, 28-29,
61) `scp`s `~/.ssh/grotap_agents` onto agent-06 as `/home/agent/.ssh/grotap_agents`. Run it after the
retirement and the key is back. It must change in the SAME commit that deletes the key, or it is a
loaded gun pointed at the whole exercise.

**RESOLVED 2026-09-16 04:46Z — and the answer shrinks the work while raising a separate alarm.**
Of the seven, exactly **one** needed a key and got one. The rest should not be touched:

| Host | Finding |
|---|---|
| `claudecode` (`claudecode.grotap.com`, user `user1`) | **Legitimate — key minted and proven.** Same physical box as `claudecode-01` (178.156.209.112), already covered under `root`; this is a second account on it, so it genuinely needed its own key. |
| `agent-01` (5.161.189.143) | **Not an agent box.** `agent` has no `.ssh` directory at all; the shared key logs in as `root`; the host identifies itself as **`grotap-cobrowse-01`** — the Cobrowse server, which the owner ordered ripped out on 2026-08-30. A leftover alias, not a fleet member. Decide decommission vs. re-purpose; do not quietly dress it up as fleet. |
| `agent-08` (77.42.42.213) | **Dead.** TCP connect to port 22 times out, confirmed twice including a raw `/dev/tcp` probe. |
| `agent-07` (89.167.66.105), `agent-09` (46.62.184.50), `agent-10` (46.62.184.52), `agent-11` (46.62.184.51) | **HOST KEY CHANGED.** `known_hosts` holds prior ed25519 and rsa records; each server now presents a different, unmatched ed25519 key. No login was attempted past the warning and nothing was appended. Consistent with these being rebuilt or reassigned — `agent-07` appears only in a stale `orchestrator/DEPLOY.md:166` list and not in live `FLEET_HOSTS`. |

**The host-key mismatch is a finding in its own right, not merely an obstacle.** All four of those IPs are
listed in the second catch-all glob in the workstation `~/.ssh/config` — the one carrying
`StrictHostKeyChecking no`. That combination means any script connecting to them **by bare IP** does
not merely fall back to the shared key, it **suppresses the host-key warning that just fired here and
connects to a machine that may no longer be ours**, authenticating with the fleet-wide credential.
The manual probe refused; the automated path would not have. This is the strongest argument yet for
deleting those glob blocks and the `StrictHostKeyChecking no` with them, and it should be raised
independently of the key retirement.

**2. Seven more hosts depend on the shared key and have no per-host key at all.** The count of
"nine remaining hosts" was itself incomplete. Also on `grotap_agents` with nothing else:
`agent-01` (5.161.189.143), `agent-07` (89.167.66.105), `agent-08` (77.42.42.213),
`agent-09` (46.62.184.50), `agent-10` (46.62.184.52), `agent-11` (46.62.184.51), and
`claudecode` (`claudecode.grotap.com`, user `user1`). Whether each is live must be established before
deletion, not assumed from its absence in `SERVERS.md`.

**3. Two catch-all IP-glob blocks in the workstation `~/.ssh/config` route bare-IP connections to the
shared key**, both with `StrictHostKeyChecking no`:

```
Host 5.161.189.143 77.42.42.213                      (User agent)
Host 5.161.74.39 5.161.81.193 178.156.222.220 5.161.73.195 5.78.178.81      89.167.66.105 46.62.184.50 46.62.184.51 46.62.184.52   (User root)
```

The second lists **all five `FLEET_HOSTS` IPs**. This is the subtle one: the per-host `Host` blocks are
keyed by NAME, but `dispatch.sh` and its siblings connect by bare IP after team routing rewrites
`SERVER_IP`. So a script that "correctly" drops its `-i` flag and relies on ssh config does not get a
per-host key — it falls past the name blocks onto the glob and gets the shared key. Everything keeps
working until the key is deleted, then fails at once, and a name-based verification sweep passes
beforehand. **The resolver must map IP to host to key explicitly, and the sweep must test a bare-IP
call, not only a named one.** Delete these globs in the same change as the key: not before, since they
are today's working fallback, and not after, since they would keep a dead path alive and mask which
scripts are still wrong.

**The one test that catches every silent-fallback case at once: a bare-IP SSH to a host that has NO
named `Host` block.** Three separate sites degrade to the shared key rather than failing, so each one
passes any check that uses a hostname:

- The two catch-all globs themselves (above).
- `agents/scripts/fleet-load.sh:145,147` — it has a per-host-aware `key_for()` at `:118-126`, but the
  call site is `[ -n "$KEY" ] && SSH_ARGS+=(-i "$KEY")`. When `key_for()` returns **empty** it connects
  with no `-i` at all, by raw IP, and lands on a glob. The one script that looks per-host-aware still
  has a silent shared-key path in it.
- `agents/scripts/fleet-model-probe.sh:78` — `ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST"`
  with no `-i` whatsoever and a comment at `:76` reading "key as that box resolves it". Entirely
  dependent on config resolution.

These two are also the only scripts that will not break outright on deletion — they will keep
"working" against any host with a named block and silently stop working for the rest. That is the same
false-green shape as the globs, which is why the sweep must include the bare-IP case explicitly.

Not a dependency, recorded so nobody counts it: `agents/scripts/orchestrator-run.sh:358-367` names
`Bash(ssh *)`, `Bash(scp *)` and `Read(**/id_rsa*)` in the agent sandbox **deny** list. It blocks
agents from using SSH; it does not consume the key.

Two smaller notes from the same sweep. `agents/scripts/fleet-load.sh:118-126` is the only script
already per-host aware (`key_for()` prefers `$SSH_KEY_DIR/grotap_$1`) — its fallback becomes dead code,
not a breakage. And `scripts/verify_slot_health.py:129,140-143` reads the base64 secret and writes a
temporary key file, so it follows the orchestrator's secret rather than any file on disk.

**A repo grep cannot see the crontab.** agent-06's cron lines exist in neither repo — only the scripts
do. Any `SSH_KEY=` override asserted in a cron line is invisible to a file survey and must be read off
the box with `crontab -l`, `crontab -l -u agent` and `systemctl list-timers`.

Once that work is done, the gate itself is a sweep of every box:

```bash
for H in agent-02 agent-03 agent-04 agent-05 agent-06 forge-01; do
  printf '%s ' "$H"
  ssh -o BatchMode=yes "$H" "cat /root/.ssh/authorized_keys /home/agent/.ssh/authorized_keys 2>/dev/null \
    | grep -c grotap-agent-farm-r2-20260705; \
    ls /root/.ssh/grotap_agents /home/agent/.ssh/grotap_agents 2>/dev/null | wc -l"
done
```

**Pass:** every host prints `0` then `0` — the shared public key (comment
`grotap-agent-farm-r2-20260705`, `SHA256:VdzajKXUHR9MF67lR45okEvGGsWL+4nWtSM4s3KceTQ`) appears in no
`authorized_keys`, and no copy of the private key remains on any box. Run the fleet's own health and
deploy crons once afterwards and confirm they still succeed.

### 8. Edge access control in front, with runner CI still green behind it

Cloudflare Zero Trust / Access is **not enabled on this account** — the API returns
`access.api.error.not_enabled`, and enabling it is a dashboard action. The current equivalent is the
zone WAF ruleset `833d63affc5d44be931d2ce74bf8f9fd`, which admits only the five worker boxes,
forge-01 and the owner workstation. The owner has decided to enable Zero Trust, so this item accepts
either control, provided CI survives it.

```bash
# from an allowed origin
curl -sS -o /dev/null -w '%{http_code}\n' -H 'User-Agent: curl/8.5.0' https://forge.grotap.com/
```

**Pass:** an allowed origin gets 200 (or the Access login page once Zero Trust is on), a non-allowed
origin is blocked, **and** item 3's canary is re-run *after* the edge change and comes back green.
The allow list **must carry each box's IPv6 /64 as well as its IPv4 address** — the boxes prefer v6,
and a v4-only list previously locked the runners out of their own forge with `failed to fetch task`.
Verify v6 explicitly rather than assuming it was inherited.

## What "cutover" can actually mean — the deploy-path constraint

*Measured 2026-09-15 against the live Railway and Vercel APIs. This section exists because the word
"cutover" implies something the deploy platforms cannot do.*

**Neither Railway nor Vercel can build from a self-hosted Forgejo.** This is a schema-level limit,
not a permissions gap or a setting nobody found. Railway's `serviceConnect` / `serviceInstanceUpdate`
mutations accept only `{ repo, image, branch }`, where `repo` is an `owner/name` slug resolved
through Railway's GitHub App installation — there is no provider field and no arbitrary git-remote
field. Vercel's `PATCH /v9/projects/{id}` accepts a `link` only for `type: github|gitlab|bitbucket`.
Forgejo/Gitea is not a supported provider on either platform.

So "point the deploy trigger at the forge" is not an action that exists. What is achievable is one of
two mechanisms, and the choice should be made explicitly.

**Owner decision, 2026-09-15: mechanism (A).** The forge becomes the push path; Forgejo push-mirrors
to GitHub; Railway and Vercel keep building from GitHub exactly as they do today, untouched. No
deploy-platform change is made, and rollback stays a `git remote set-url` away. The reverse push
mirror is therefore the enabling work for this migration, and it does not exist yet on any repo.
Mechanism (B) is not being pursued now; it is recorded below so the option is not re-derived later.

- **(A) Forge is the push path; GitHub stays the deploy trigger.** Humans and agents push to
  `forge.grotap.com`; Forgejo **push-mirrors** to GitHub; Railway and Vercel keep building from
  GitHub exactly as they do today. This is what the "move the push path first" step in the sequencing
  below already describes, and it needs no deploy-platform change at all.
- **(B) CI-driven deploys from the forge.** Replace the GitHub Actions workflows with Forgejo
  Actions workflows (the YAML is compatible, and `forgejo-runner` already runs on agent-02..06) that
  run the same `railway up` / `vercel deploy` CLI commands. Railway and Vercel then never see a git
  provider at all.

**Most of the estate is already on mechanism (B) and does not know it.** Measured today:

| Target | Deploy source | Can it move to the forge? |
|---|---|---|
| Vercel `grotapfrontend`, `grotap-landing`, `frontend` | **No git link at all** (`link: null`) — deployed by `.github/workflows/deploy-frontend.yml` running `vercel build` / `vercel deploy --prebuilt` | Yes — swap the workflow to Forgejo Actions; Vercel is already provider-agnostic here |
| Railway `orchestrator`, `claude-runner` | `source.repo = null`, no triggers — deployed by `.github/workflows/deploy-railway.yml` running `railway up --service <id>` | Yes — same swap |
| Railway `backend-worker` | git-sourced, but no push-trigger row | Convert to `railway up` like the two above |
| Railway `grotap-backend`, `grotap-ingestion-worker`, `grotap-agent-worker` | **Native GitHub webhook trigger**, branch `master` | **No.** Either GitHub stays the trigger (mechanism A), or these three are converted to the `railway up` pattern already proven for `orchestrator` |

Railway API note for whoever runs this next: **`RAILWAY_TOKEN` is the token that works**, and only
as the header `Project-Access-Token: <token>` — not `Authorization: Bearer`. `RAILWAY_API_TOKEN`
does not authenticate against this API at all. Send a real `User-Agent`; a bare urllib UA gets 403.
Project `grotap-platform` is `f9bf333c-f929-413e-a95c-7923e10b5777`, environment `production` is
`02a294e0-f3f9-4530-85c5-9142c7e097b0`.

### The reverse push mirror does not exist yet

`GET /api/v1/repos/Grotap-AI/<repo>/push_mirrors` returns `[]` for **all four** repositories. The
rollback section below depends on GitHub never being more than ten minutes behind, and mechanism (A)
depends on the push mirror outright — it *is* the deploy path. **Nothing may be cut over until the
push mirror is configured and proven**, in the direction opposite to today's.

### Fleet references that a push-path move would break

These read GitHub directly and are not fixed by changing a remote:

- `agents/dispatch.sh:328,613,945` and `agents/scripts/orchestrator-run.sh:224` — bootstrap
  `git clone https://github.com/Grotap-AI/grotap-agents.git` on every agent run (unpinned; this is
  the known P1-B risk).
- `agents/scripts/review-gate-cron.sh:291` — clones `grotap-platform` from GitHub.
- `agents/scripts/dispatch-poller.sh:19,31-32,49,85` — calls the **GitHub REST Contents API**
  (`https://api.github.com/repos/Grotap-AI/grotap-agents/contents/...`) to read and write pending
  task files. This one needs a Forgejo Contents-API equivalent, not a hostname substitution.

## Canary-first sequencing

Cut over **one low-risk repository first** and leave `grotap-platform`'s deploy path on GitHub until
that canary is boring.

**Take `grotap-platform-docs` first.** No Railway service and no Vercel project builds from it, it
carries no CI workflows to re-home, and it is not cloned locally at all — the working docs live
inside `grotap-agents` — so a mistake there cannot wedge anyone's tree or take a deploy down. If a
richer second test is wanted, take `grotap-agents` next: nothing deploys from it either, but
`dispatch.sh` bootstraps from it on every agent run, so a wrong clone URL stops the whole fleet
rather than one document.

**"Boring" means 14 consecutive days** in which the item 1 parity check ran daily and never diverged;
at least **20 Actions runs completed green** on the forge runners with zero infrastructure-caused
failures (a failing test is fine, a runner that cannot fetch a task is not); there was no unplanned
forge restart; and at least one backup taken inside that window was restored and verified. Because
the fleet is capped until 2026-10-01, those 20 runs must be produced deliberately — ambient agent
traffic will not supply them.

Only after that does `grotap-platform` move, and even then in two steps: move the **push path**
first and let the mirror carry commits back to GitHub for a full boring window, then move the
**deploy trigger**.

## Rollback

Rollback takes minutes because GitHub keeps a complete, current copy of every repository. Preserving
that property is a standing condition of this migration, not an incidental benefit: after cutover
the mirroring direction inverts, and the forge must **push-mirror to GitHub** so that GitHub is never
more than ten minutes behind. If that reverse mirror ever stops, the rollback below stops being
cheap, and the cutover should be treated as reverted until it is fixed.

Per clone — point the remote back at GitHub:

```bash
git remote set-url origin https://github.com/Grotap-AI/grotap-platform.git
git remote -v && git fetch origin && git status -sb
```

On the fleet the same `git remote set-url` runs against each box's checkout. `agents/dispatch.sh`
bootstraps from `grotap-agents`, so its clone URL reverts with it and must be checked before the
next dispatch.

Deploy sources are dashboard actions and are not scripted today. In **Railway**, reconnect each
affected service's source to the GitHub repository and branch, then trigger a redeploy. In
**Vercel**, go to Project → Settings → Git, reconnect the GitHub repository, then redeploy. Verify
by pushing a trivial commit to GitHub and watching a build start from it.

## Known risks accepted

- **SQLite on a single cpx21.** The database is one file (`/opt/forge/forgejo/gitea/gitea.db`,
  2.4 MB; `/opt/forge` totals 136 MB against 68 GB free of 75 GB). The size is a non-issue; the
  absence of a replica is not. Item 6 is the only thing standing between this and data loss, and as
  of 2026-09-15 it holds only half: a restore has been proven, but no backup is being taken on a
  schedule, so the protection is as old as the last hand-run dump.
- **One box, one region.** A Hetzner Ashburn incident takes the forge and all CI with it, and after
  cutover it would take the source of truth too. This is the reason GitHub must remain a live mirror
  target indefinitely.
- **The webhook cannot start agent runs.** Deliberate: letting a forge push spawn execution would
  hand anyone who can write to a branch a way to run code. Work continues to come from
  `pipeline_cases` via the assign loop.
- **Zero Trust is pending.** Until it is enabled the WAF ruleset is the only edge control, and it is
  an IP allow list — it authenticates networks, not people.

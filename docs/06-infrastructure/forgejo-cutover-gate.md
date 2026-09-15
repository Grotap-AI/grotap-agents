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
and are never typed inline. Two environmental gotchas will otherwise waste your time: the
workstation and the five worker boxes are on the forge's edge allow list and anything else gets a
Cloudflare block rather than an application error, and Cloudflare rejects a bare `urllib` user agent
with a 403 (error 1010), so HTTP probes must send a real `User-Agent`.

## Go / no-go checklist

### 1. Mirror head parity — the primary signal

Compare each mirror's default-branch head on the forge against the same ref on GitHub. This beats an
elapsed-time check outright: a mirror that has silently stopped fetching still advances its
`mirror_updated` timestamp on every scheduled attempt, so it looks fresh while serving a stale tree.
A divergent head cannot hide that way.

```bash
doppler run -p grotap -c prd -- bash -c '
for R in grotap-platform grotap-agents grotap-landing grotap-platform-docs; do
  META=$(curl -sf -H "Authorization: token $FORGE_API_TOKEN" "$FORGE_URL/api/v1/repos/Grotap-AI/$R")
  BR=$(printf "%s" "$META" | python -c "import sys,json;print(json.load(sys.stdin)[\"default_branch\"])")
  FG=$(curl -sf -H "Authorization: token $FORGE_API_TOKEN" "$FORGE_URL/api/v1/repos/Grotap-AI/$R/branches/$BR" \
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
  curl -sf -H "Authorization: token $FORGE_API_TOKEN" "$FORGE_URL/api/v1/repos/Grotap-AI/$R" \
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
repo showed `18:24:48`, correctly scheduled ten minutes forward. A mirror whose `next_update_unix` is
behind `now()` is stuck, no matter how fresh `updated_unix` looks.

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
doppler run -p grotap -c prd -- bash -c 'curl -sf -H "Authorization: token $FORGE_API_TOKEN" \
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

**Owner action required:** create a Wasabi sub-user scoped to the forge backup bucket from an account
with IAM rights, store its key pair in Doppler, and write it into `/root/.forge-backup.env` on
forge-01.

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
- Update `agents/SERVERS.md`, which still documents the shared key as the root SSH method — grep it
  for `grotap_agents` (currently one occurrence, line 92).
- Only then remove the public key from every `authorized_keys` and delete the private key from
  agent-06 and agent-04.

**Grep for the string, not the line number.** Both references above have already moved once:
`health-monitor.sh` went from line 59 to 64 when commit `6bd54b4` fixed that file's roster and added
a comment block above the call, and `SERVERS.md` went from two hits (lines 82 and 92) to one when a
forge-01 row was inserted and shifted what used to be line 82. The `ssh -i /home/agent/.ssh/grotap_agents`
invocation itself is unchanged and remains a genuine blocker. Line numbers in a blocker list rot
faster than anything else in it, so treat the numbers here as a hint and the string as the check:

```bash
grep -rn 'grotap_agents' agents/scripts/health-monitor.sh agents/SERVERS.md
```

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

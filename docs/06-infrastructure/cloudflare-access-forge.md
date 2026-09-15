# Cloudflare Zero Trust / Access in front of `forge.grotap.com`

**Audience:** the owner, clicking through the Cloudflare dashboard.
**Written:** 2026-09-15. Every "current state" fact below was measured live against the Cloudflare
API on that date, not recalled.
**Why a document instead of a script:** Zero Trust has never been enabled on this Cloudflare
account, and the Access API refuses every call until it is. The exact error the API returns today is
`access.api.error.not_enabled: Access is not enabled. Visit the Access dashboard at
https://dash.cloudflare.com/ and click the 'Enable Access' button.` There is no API, CLI or
Terraform path around that first click — it is a one-time account-level action that only a human
with dashboard access can perform. Everything after that first click *can* be automated, but the
steps below are written as click-paths so you can do the whole thing in one sitting without waiting
on me.

---

## 1. What this protects, and what it does not

Cloudflare Access sits at Cloudflare's edge and challenges **HTTP requests** to a hostname before
they reach the origin. Applied to `forge.grotap.com`, it will put an identity check in front of the
Forgejo web UI and the Forgejo REST API.

It will **not** protect git-over-SSH. `forge-ssh.grotap.com` resolves to an **unproxied** A record on
port **2222**, because Cloudflare's proxy cannot carry git's SSH transport. That traffic never
touches Cloudflare at all, so no Access policy can see it, allow it or block it. SSH to the forge is
protected only by the Hetzner firewall `forge-fw` (port 2222 open to the five worker boxes and the
owner workstation) and by the forge's own SSH key authentication. Do not let anyone conclude that
"the forge is behind Access" means the SSH path is covered — it is not, and it is the path all the
real git traffic uses.

Access is also an **additional** layer, not the only one. Forgejo itself already runs with
`DISABLE_REGISTRATION` and `REQUIRE_SIGNIN_VIEW` enabled, so an unauthenticated visitor already sees
nothing but a sign-in form. Access moves that boundary out to Cloudflare's edge, so an attacker never
reaches the Forgejo application code in the first place. After this change a human visiting the forge
signs in **twice**: once to Cloudflare Access, then once to Forgejo. That is expected and correct.

---

## 2. Current state (verified 2026-09-15)

| Thing | Value |
|---|---|
| Cloudflare account | `Info@grotap.com's Account`, id `25c5bc14485348a4e9690aada1962818` |
| Zone | `grotap.com`, id `a589e163cb028b700d725fa08d5bb009` |
| Zero Trust / Access | **not enabled** — API returns `access.api.error.not_enabled` |
| `forge.grotap.com` | A record, **proxied** (orange cloud) → forge-01 `178.156.246.81` |
| `forge-ssh.grotap.com` | A record, **unproxied**, port 2222 — Cloudflare cannot proxy git-SSH |
| Origin web server | Caddy in `/opt/forge`, config `/opt/forge/caddy/Caddyfile` |
| Caddy config today | `forge.grotap.com { encode gzip; reverse_proxy forgejo:3000 }` — no auth, no JWT validation |
| Existing protection | Zone WAF ruleset `833d63affc5d44be931d2ce74bf8f9fd`, named `forge-access-lock`, phase `http_request_firewall_custom` |
| That ruleset's single rule | `block` everything where `http.host eq "forge.grotap.com"` and the source IP is not in the allow set: the five worker boxes, forge-01, the owner workstation `98.97.42.234`, and six IPv6 `/64` prefixes for the worker boxes |
| Runner → forge URL | `https://forge.grotap.com` (read from `/opt/forgejo-runner/.runner` on agent-02) — i.e. the **proxied** hostname, so Access will land directly in the runners' path |
| Runner request path | `/api/actions/runner.v1.RunnerService/FetchTask` (observed in the live Caddy access log) |

Because the origin has no JWT-validation directive, Access will be enforced **only at Cloudflare's
edge**. Anything that reaches forge-01 by IP, or from inside the Cloudflare IP ranges the WAF admits,
bypasses Access entirely. That is the standard reason to keep the WAF layer in place underneath —
see §7.

---

## 3. The one thing that will break this if you get it wrong

The worker boxes prefer IPv6. When the forge WAF allow-list was first written with IPv4 addresses
only, every runner silently lost its own forge and CI died with `failed to fetch task`. The fix was to
add the six IPv6 `/64` prefixes you can see in the rule above. That was an expensive lesson and it
will repeat, in a harder-to-diagnose form, if the Access policy is built around IP addresses.

**Therefore: no Access policy in this design may use an IP-address selector.** Machines are admitted
by **service token**; humans are admitted by **email**. An identity-only Access application — one that
requires a person to click through a login screen — will break every runner the moment you save it,
because `forgejo-runner` has no browser and no human at the keyboard.

There is a second, sharper edge to this. I checked the runner's own configuration surface on agent-02:
`forgejo-runner generate-config` and `forgejo-runner daemon --help` expose **no option for custom HTTP
headers**. That means the runner *cannot* be told to send the `CF-Access-Client-Id` and
`CF-Access-Client-Secret` headers that a service token requires. A service token protects the API
calls that *we* control — the backend, `curl`, dispatch tooling, anything where we write the request —
but it cannot be pushed into the runner daemon itself.

This is why the design below carves the runner's own protocol path out with a **Bypass** policy
(§5, step 4) and leans on the WAF underneath it for that one path, while using service tokens for
everything else machine-driven. Do not skip that step, and do not "tidy it up" later by deleting it.

---

## 4. Order of operations

Follow this order exactly. It is arranged so that at no point is there a window where the runners are
locked out.

1. Enable Zero Trust on the account.
2. Create the service tokens **first** — before any application exists. Tokens with no application to
   guard are harmless; an application with no tokens is an outage.
3. Store the token pairs in Doppler.
4. Create the **path-scoped Bypass application** for `/api/actions` — before the main application.
   Access evaluates the most specific path match first, so this must exist before the broad
   application starts challenging.
5. Create the **`/api/v1` service-auth application**.
6. Only then create the **main application** for the whole hostname.
7. Verify (§8) before you walk away.

---

## 5. The click path

### Step 1 — Enable Zero Trust on the account

1. Go to <https://dash.cloudflare.com/> and sign in as `info@grotap.com`.
2. In the left sidebar, select **Zero Trust**. (On some dashboard versions this opens
   <https://one.dash.cloudflare.com/> in place of the main dashboard; either is fine.)
3. Cloudflare will ask you to choose a **team domain** — the hostname your logins happen on. Enter
   `grotap`. Your team domain becomes `grotap.cloudflareaccess.com`. Choose carefully: changing it
   later invalidates every existing Access session and every application that references it.
4. Choose the **Free** plan when prompted. It covers up to 50 seats, which is far more than this
   needs. Cloudflare will ask for a payment method even on the free plan; that is normal and the plan
   bills at zero.
5. Finish the setup wizard. When it lands you on the Zero Trust overview page, Access is enabled.

Once this is done, tell me — from that point I can do the remaining steps by API if you would rather
not click through them, and I can verify them either way.

### Step 2 — Create the service tokens (do this before any application)

Navigate to **Access → Service authentication → Service tokens** (older dashboards label this
**Access → Service Auth**). Click **Create service token** once per token below.

Create **six** tokens. Give each a duration of **1 year** (the longest non-permanent option) and note
the expiry — a silently expired service token looks exactly like a broken CI runner.

| Token name | Used by |
|---|---|
| `forge-runner-agent-02` | forgejo-runner on agent-02 |
| `forge-runner-agent-03` | forgejo-runner on agent-03 |
| `forge-runner-agent-04` | forgejo-runner on agent-04 |
| `forge-runner-agent-05` | forgejo-runner on agent-05 |
| `forge-runner-agent-06` | forgejo-runner on agent-06 |
| `forge-01-self` | forge-01 itself, and platform tooling that calls the Forgejo REST API with `FORGE_API_TOKEN` |

**Cloudflare shows each token's Client Secret exactly once, at creation time.** Copy both the
`Client ID` and the `Client Secret` for each token into a scratch file as you go. If you lose a
secret the only remedy is to delete the token and create a new one.

Separate tokens per host is deliberate: it means a compromised box can be revoked on its own without
taking the other four runners down with it.

### Step 3 — Hand me the tokens for Doppler

Send me the six ID/secret pairs (or paste them into a local file and tell me the path) and I will
store them in Doppler `grotap` prd and dev as:

```
FORGE_ACCESS_CLIENT_ID_AGENT02 … _AGENT06
FORGE_ACCESS_CLIENT_SECRET_AGENT02 … _AGENT06
FORGE_ACCESS_CLIENT_ID_FORGE01
FORGE_ACCESS_CLIENT_SECRET_FORGE01
```

Do not put them in a GitHub secret, a `.env` in a repo, or a chat message that outlives the session.

### Step 4 — Create the runner-path Bypass application FIRST

This is the step that keeps CI alive. Go to **Access → Applications → Add an application → Self-hosted**.

1. **Application name:** `forge-runner-protocol`
2. **Session duration:** leave at the default; it is irrelevant for a bypassed path.
3. **Application domain:** subdomain `forge`, domain `grotap.com`, **path** `api/actions`.
   Cloudflare writes this as `forge.grotap.com/api/actions`. It covers
   `/api/actions/runner.v1.RunnerService/*`, which is the exact path the runners were observed using
   in the live Caddy log.
4. Save and continue to policies.
5. Add one policy:
   - **Policy name:** `runner-protocol-bypass`
   - **Action:** **Bypass**
   - **Include:** selector **Everyone**
6. Save.

A Bypass policy means Access does not challenge that path at all. The protection for it remains the
WAF rule `forge-access-lock`, which already admits only the five workers, forge-01 and your
workstation — including their IPv6 prefixes. That is the whole reason §7 insists the WAF stays.

If Forgejo's runner protocol path ever changes (a Forgejo major upgrade could move it), CI will start
failing with an Access HTML page instead of a task. The symptom to look for is `failed to fetch task`
in `journalctl -u forgejo-runner` on any worker box.

### Step 5 — Create the `/api/v1` service-auth application

The Forgejo REST API lives at `https://forge.grotap.com/api/v1/*`. Our own tooling calls it with
`FORGE_API_TOKEN`. Those callers are scripts we write, so they *can* send Access headers.

1. **Add an application → Self-hosted.**
2. **Application name:** `forge-api`
3. **Application domain:** `forge` . `grotap.com`, **path** `api/v1`.
4. In **Settings**, enable **Accept Service Auth tokens** if the version of the dashboard you are on
   shows that toggle. (On current dashboards it is implicit once a Service Auth policy exists.)
5. Policies — add **two**, in this order:
   - **Policy 1 — `api-service-tokens`**, action **Service Auth**, Include: selector
     **Service Token** → select all six tokens from Step 2. (The **Any Access Service Token**
     selector also works and needs no maintenance when tokens are added, at the cost of admitting any
     future token on the account. Prefer the explicit six.)
   - **Policy 2 — `api-owner`**, action **Allow**, Include: selector **Emails** →
     `info@grotap.com`. This is what lets you poke the API from a browser session.
6. Make sure the Service Auth policy is **above** the Allow policy in the list. Access evaluates in
   order, and a token-bearing request should never fall through to an identity check.

After this, any script that calls the Forgejo REST API must send two extra headers:

```
CF-Access-Client-Id: <client id>
CF-Access-Client-Secret: <client secret>
```

I will update the platform tooling that calls `FORGE_URL/api/v1/...` to read those from Doppler and
attach them. Until that lands, those scripts will start receiving an Access HTML login page instead
of JSON — which is the failure mode to watch for.

### Step 6 — Create the main application for the hostname

Only now create the broad application.

1. **Add an application → Self-hosted.**
2. **Application name:** `forge-web`
3. **Session duration:** **24 hours** is a reasonable default for a tool you use daily.
4. **Application domain:** `forge` . `grotap.com`, **path left empty** — this covers the whole
   hostname. The two path-scoped applications from Steps 4 and 5 take precedence over it for their
   paths, because Access matches the most specific path first.
5. Under **Settings → Identity providers**, leave **One-time PIN** enabled. It emails a six-digit code
   to an allowed address, needs no external IdP, and is sufficient for a single-owner tool. (If you
   later want Google sign-in, add the Google IdP under **Settings → Authentication** and it becomes
   an option here without changing the policies.)
6. Policies — add **two**, in this order:
   - **Policy 1 — `web-service-tokens`**, action **Service Auth**, Include: **Service Token** → the
     same six tokens. This is belt-and-braces: it catches any machine call that lands on a path the
     two specific applications do not cover.
   - **Policy 2 — `web-owner`**, action **Allow**, Include: selector **Emails** → `info@grotap.com`.
     Add any other staff address here later; one address per line.
7. Save.

### Step 7 — What you should see immediately

Open `https://forge.grotap.com` in a browser. You should now get a **Cloudflare Access** page asking
for your email and a one-time PIN, *before* the Forgejo sign-in page. After the PIN, you land on the
familiar Forgejo sign-in form. Both layers are expected.

---

## 6. Consequences to expect

- **Git clone over HTTPS from a human machine will break.** `git clone https://forge.grotap.com/...`
  has no browser to complete an Access challenge, so it receives an HTML login page and fails with a
  confusing error. Use the SSH remote instead: `ssh://git@forge-ssh.grotap.com:2222/...`. This costs
  us nothing today, because all four repos are pull mirrors that forge-01 fetches **from GitHub**
  (outbound, unaffected), and nobody clones from the forge over HTTPS.
- **The mirrors keep working.** They are outbound HTTPS from forge-01 to GitHub. Access never sees
  them.
- **Webhooks from the forge keep working.** `POST /api/v1/forgejo/pipeline-sync` is outbound from
  forge-01 to `api.grotap.com`, so Access in front of `forge.grotap.com` does not gate it — it is
  authenticated by an HMAC signature keyed on `FORGEJO_WEBHOOK_SECRET`. That webhook records pushes
  only and deliberately cannot start an agent run, so a green webhook is not evidence that the forge
  can drive the fleet.
- **Nothing about the Caddyfile changes.** Caddy stays a plain `reverse_proxy forgejo:3000`. Adding
  origin-side JWT validation (so forge-01 rejects anything that did not come through Access) is a
  worthwhile hardening step, but it is a separate change with its own lockout risk and it is not part
  of this one.

---

## 7. Keep the WAF underneath — do not replace it

Leave the zone WAF ruleset `833d63affc5d44be931d2ce74bf8f9fd` (`forge-access-lock`) exactly as it is.
It is not redundant with Access; the two cover different failures.

- Access is bypassed on `/api/actions` by design (§5 step 4). On that path the WAF rule is the **only**
  thing standing between the open internet and the runner protocol.
- Access is enforced only at Cloudflare's edge, because the origin does no JWT validation. A request
  that reaches forge-01 another way is not checked by Access at all.
- A misconfigured or accidentally deleted Access application fails **open**. A WAF block rule fails
  **closed**.

If you later add an IP to that WAF rule, add its **IPv6 prefix too**. Every worker box in that list
has both.

---

## 8. Rollback

If anything goes wrong — runners failing, tooling 403ing, yourself locked out — the rollback is fast
and safe:

1. Go to **Zero Trust → Access → Applications**.
2. Delete (or set every policy to **Bypass / Everyone** on) the applications `forge-web`, `forge-api`
   and `forge-runner-protocol`, in that order — broadest first.
3. Within a minute the edge stops challenging and `https://forge.grotap.com` returns the plain Forgejo
   sign-in page again.

The host is **not** left exposed by this rollback: the WAF ruleset `forge-access-lock` is untouched
and still admits only the five workers, forge-01 and your workstation, and Forgejo's own
`REQUIRE_SIGNIN_VIEW` / `DISABLE_REGISTRATION` are still on. You are back to exactly the security
posture of 2026-09-15, not to an open forge.

Deleting the Access **applications** is enough. You do not need to disable Zero Trust on the account,
and you should not — turning it off and on again churns the team domain.

---

## 9. What I verify after you click

Tell me when Step 6 is saved and I will run these, in this order, and report each result:

1. **Edge behaviour from an allowed host.** `curl -sI https://forge.grotap.com/` from the owner
   workstation should return a redirect or challenge from Cloudflare Access rather than the Forgejo
   sign-in HTML — confirming Access is actually in the path and not silently absent.
2. **Service token works.** `curl` against `https://forge.grotap.com/api/v1/version` with the
   `CF-Access-Client-Id` / `CF-Access-Client-Secret` headers from the `forge-01-self` token should
   return Forgejo JSON, not an HTML login page. The same call **without** those headers should be
   challenged. Both halves matter — the negative test is what proves the policy is real.
3. **The runner path is still open to runners.** `curl -sI
   https://forge.grotap.com/api/actions/runner.v1.RunnerService/FetchTask` from a worker box should
   *not* return an Access challenge.
4. **A real CI run.** Re-run the `Grotap-AI/forge-smoke` workflow and confirm a runner picks it up and
   it goes green. This is the only test that proves the whole chain end to end; the curl checks can
   all pass while CI is still broken.
5. **Runner logs are clean.** `journalctl -u forgejo-runner -n 50` on each of agent-02…06, checked for
   `failed to fetch task`.
6. **`POST /api/v1/forgejo/pipeline-sync` still returns 202 on a signed push.** This route is live on
   `origin/master` (`backend/app/routers/forgejo.py`, landed in `f86d599ed`, registered in
   `main.py:289`, covered by `backend/tests/test_forgejo_webhook.py`). It authenticates with an
   HMAC-SHA256 signature over the raw body — `X-Forgejo-Signature`, or `X-Hub-Signature-256` as a
   fallback — keyed by `FORGEJO_WEBHOOK_SECRET`, and it is exempted by prefix from
   `TenantAuthMiddleware`, so it does not need `X-Node-Secret`. I will replay a correctly signed push
   payload and confirm a `202 Accepted`, and separately hit its `GET /api/v1/forgejo/health` sibling,
   which returns `{"ok": true, "configured": <bool>}` and distinguishes "route missing" from "route
   present but unconfigured".

   This is a good regression check **precisely because it should be unaffected**: the route lives on
   `api.grotap.com`, not on the forge, and is gated by HMAC rather than by Access, so putting Access
   in front of `forge.grotap.com` must not change its behaviour at all. If it does, something in the
   Access setup touched more than it should have.

   One thing not to misread: this webhook **records pushes only and deliberately cannot start an
   agent run** — a green 202 means the forge can talk to the control plane, not that the forge can
   drive the fleet.

I will also re-read the WAF ruleset afterwards to confirm nothing in the Access setup wizard modified
it.

---

## 10. Things I could not verify, and you should know about

- **Checking whether backend code exists: read `origin/master`, not the working tree.** The shared
  checkout at `C:\1Claude\platform` is deliberately left parked behind `origin/master` (198 commits
  behind, as of writing this) because several sessions share it. A `grep` or `ls` of the working
  directory therefore reflects a stale snapshot, not the codebase. Use `git ls-tree origin/master
  <dir>` and `git show origin/master:<path>`. This caught me out on the `/api/v1/forgejo/*` route
  above, which I first reported as missing when it has been live since `f86d599ed`. The line in
  `platform/CLAUDE.md` listing that route as an open item is itself stale — it predates that commit —
  so it corroborated the wrong answer.
- **Whether the dashboard labels match exactly.** Cloudflare renames Zero Trust navigation items
  fairly often (`Service Auth` → `Service authentication`, `Access` moving between the main dashboard
  and `one.dash.cloudflare.com`). If a label below does not match what you see, use the dashboard
  search box for the noun — `service token`, `application`, `policy` — rather than hunting the tree.
  The structure and the order of operations are what matter and those have been stable.
- **The exact behaviour of a Service Auth policy on the runner protocol path.** I did not test it,
  because I cannot create an Access application until Zero Trust is enabled. The Bypass carve-out in
  Step 4 exists precisely so we do not have to find out the hard way with CI down.
- **Whether `forgejo-runner` could be made to send Access headers by some route I did not find.** Its
  config schema and daemon flags expose no header option, and an `HTTPS_PROXY` cannot inject headers
  into a TLS tunnel. If a future Forgejo release adds one, the Bypass application in Step 4 can be
  replaced with a Service Auth policy and the security posture improves.

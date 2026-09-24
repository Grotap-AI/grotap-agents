# forge-01 Disaster Recovery

Recovery procedure for the Forgejo host behind `https://forge.grotap.com`. Written and verified
2026-09-15 against the live box; every value below was read from the running system, the Hetzner
API, the Cloudflare API or Doppler, not copied from a design document.

## What a total loss actually costs

**GitHub is still the source of truth.** All four repositories on the forge — `grotap-platform`,
`grotap-agents`, `grotap-landing`, `grotap-platform-docs` — are *pull mirrors* of their GitHub
counterparts, refreshed every ten minutes, and Railway and Vercel still build from GitHub. Losing
forge-01 today therefore costs CI (the five `forgejo-runner` daemons have nothing to talk to) and
the forge's own metadata: user accounts and password hashes, the `platform-automation` API token,
the `pipeline-sync` webhook configuration, runner registrations, and any issue or pull-request
state created on the forge itself. It does **not** cost source code. The only repository that is
not mirrored is `forge-smoke`, a 24 KB smoke-test repo created on the forge.

Because of that, restoring the backup is the preferred path but never the blocking one: a rebuilt
forge can always re-create the four mirrors from GitHub and re-register the runners by hand.

## Facts you will need

| Item | Value |
|---|---|
| Server | Hetzner Cloud `forge-01`, ID `166078095`, type `cpx21`, image `ubuntu-24.04`, Ashburn |
| Address | `178.156.246.81`, IPv6 `2a01:4ff:f0:efa6::/64` |
| Cost | EUR 37.49/mo gross |
| Stack | `docker compose` in `/opt/forge` — `forgejo` (`codeberg.org/forgejo/forgejo:13`, currently 13.0.5) and `caddy` (`caddy:2`) |
| Database | sqlite3 at `/opt/forge/forgejo/gitea/gitea.db` (~2.5 MB), config `/opt/forge/forgejo/gitea/conf/app.ini` |
| Backups | `s3://grotap-forge-backups/forge-01/<YYYY>/<MM>/forge-<UTC timestamp>.zip`, Wasabi `s3.us-west-1.wasabisys.com`, region `us-west-1`, SSE-S3 AES256 |
| Hetzner firewall | `forge-fw`, ID `11628446` |
| Cloudflare | zone `a589e163cb028b700d725fa08d5bb009`, custom ruleset `833d63affc5d44be931d2ce74bf8f9fd` ("forge-access-lock") |
| Allowed sources | agent-01-claude `5.161.74.39`, agent-02-claude `5.161.81.193`, agent-03-claude `178.156.222.220`, agent-04-claude `5.161.73.195`, agent-05-claude `5.78.178.81` (Hillsboro, powered off), agent-06-claude `5.161.53.103`, owner workstation `98.97.42.234` |
| Credentials | Doppler `grotap` prd+dev: `FORGE_URL`, `FORGE_API_TOKEN`, `FORGE_ADMIN_USER`, `FORGE_ADMIN_PASSWORD`, `FORGEJO_WEBHOOK_SECRET`, `FORGE_SSH_HOST`, `FORGE_SSH_PORT`, `FORGE_SERVER_IP`, `WASABI_FORGE_*` |

forge-01 deliberately holds **no Doppler token** and must never be given one. Its only secret on
disk is `/root/.forge-backup.env` (root-owned, `0600`), which carries the scoped Wasabi sub-key.

## Step 1 — Rebuild the host

Create a replacement from the workstation using `HETZNER_API_TOKEN` (the `POST /v1/servers` call
takes `name=forge-01`, `server_type=cpx21`, `image=ubuntu-24.04`, `location=ash`, the fleet SSH key,
and `firewalls=[{"firewall":11628446}]`). Attaching the existing firewall at create time means the
box is never briefly open to the internet. Then install Docker and the compose plugin:

```bash
ssh root@<new ip> 'apt-get update && apt-get install -y ca-certificates curl && \
  install -m 0755 -d /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
    > /etc/apt/sources.list.d/docker.list && \
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin python3-boto3'
```

Recreate `/opt/forge/docker-compose.yml` and `/opt/forge/caddy/Caddyfile` from the snapshots in
`docs/06-infrastructure/forge-01/` (`docker-compose.yml.snapshot`, `Caddyfile.snapshot`, taken
2026-09-15; the live files are owned by the forge-provisioning work, so check for a newer copy
there first). The compose file mounts `./forgejo:/data` and `./backups:/backups`, publishes
`2222:2222` for Forgejo's built-in SSH server, and Caddy publishes `80:80` and `443:443`. Create
`/opt/forge/backups` as `0700` owned by uid/gid `1000`. Do **not** start the stack yet.

## Step 2 — Restore the data from Wasabi

Fetch the most recent object and unpack it. The dump is a credential in its own right — it contains
`app.ini` with `SECRET_KEY`, `INTERNAL_TOKEN` and the OAuth2 JWT secret, the sqlite database with
password hashes and API token hashes, and every repository — so keep it `0600` and delete it when
you are done.

```bash
export AWS_ACCESS_KEY_ID=$(doppler secrets get WASABI_FORGE_ACCESS_KEY_ID --plain -p grotap -c prd)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get WASABI_FORGE_SECRET_ACCESS_KEY --plain -p grotap -c prd)
aws --endpoint-url https://s3.us-west-1.wasabisys.com s3 ls --recursive s3://grotap-forge-backups/forge-01/
aws --endpoint-url https://s3.us-west-1.wasabisys.com s3 cp \
    s3://grotap-forge-backups/forge-01/<YYYY>/<MM>/forge-<ts>.zip /tmp/restore.zip
```

The archive holds four top-level entries: `app.ini`, `forgejo-db.sql`, `repos/` and `data/`. Lay
them out so that `data/` becomes `/opt/forge/forgejo/gitea`, `repos/` becomes
`/opt/forge/forgejo/git/repositories`, and `app.ini` becomes
`/opt/forge/forgejo/gitea/conf/app.ini`. Rebuild the database from the SQL dump rather than trusting
the `data/gitea.db` the archive also carries:

```bash
rm -f /opt/forge/forgejo/gitea/gitea.db*
python3 -c "import sqlite3; c = sqlite3.connect('/opt/forge/forgejo/gitea/gitea.db'); \
c.executescript(open('/tmp/unpack/forgejo-db.sql', encoding='utf-8').read()); c.commit(); c.close()"
chown -R 1000:1000 /opt/forge/forgejo && rm -rf /tmp/restore.zip /tmp/unpack
cd /opt/forge && docker compose up -d
```

Confirm the stack with `docker exec caddy wget -qSO /dev/null http://forgejo:3000/`, which should
return `200 OK`, and the same call against `/api/v1/version`, which should return `403 Forbidden`
because `REQUIRE_SIGNIN_VIEW` is on. A 403 there is the healthy answer, not a fault.

## Step 3 — DNS and the edge allow list

Two records exist in the `grotap.com` zone: `forge.grotap.com`, an A record that is **proxied**
through Cloudflare, and `forge-ssh.grotap.com`, an A record that is **not** proxied, because
git-over-SSH cannot traverse the HTTP proxy. Repoint both at the new address with
`CLOUDFLARE_EDGE_TOKEN` against `PATCH /zones/<zone>/dns_records/<record id>`.
`CLOUDFLARE_API_TOKEN` is not sufficient and returns 403 on the DNS endpoints.

If the replacement box takes a new IPv4 or IPv6 address, three allow lists need the new value. The
Hetzner firewall `forge-fw` restricts ports 22, 2222 and ICMP to the fleet and workstation sources
listed above, while 80 and 443 are already restricted to the fifteen published Cloudflare ranges.
The Cloudflare `forge-access-lock` custom rule blocks `http.host eq "forge.grotap.com"` unless
`ip.src` is in the fleet set; that set includes forge-01's own IPv6 `/64` as well as each agent
box's `/64`, so a new IPv6 prefix must be added there too. Finally, update `FORGE_SERVER_IP` in
Doppler prd and dev, and any `ssh_config` entry or automation that pins the address.

## Step 4 — Re-register the runners

Each of agent-01-claude through agent-05-claude runs `forgejo-runner` v13.1.0 from `/opt/forgejo-runner` as the
unprivileged `forge-runner` user under `forgejo-runner.service`. Registration state lives in
`/opt/forgejo-runner/.runner`. A restored database brings the five registrations back with it and
the runners reconnect on their own; verify with `systemctl is-active forgejo-runner` on each box and
by confirming that `action_runner` still holds five rows. If the database could not be restored,
mint a fresh org-level registration token in the Forgejo UI under `Grotap-AI` and, on each box:

```bash
ssh root@<agent ip> 'systemctl stop forgejo-runner && rm -f /opt/forgejo-runner/.runner && \
  sudo -u forge-runner /opt/forgejo-runner/forgejo-runner register --no-interactive \
    --instance https://forge.grotap.com --token <registration token> \
    --name <agent-0N-claude> --labels "ubuntu-latest:host,ubuntu-24.04:host" && \
  systemctl start forgejo-runner'
```

## Step 5 — Re-arm the backup

All five backup artifacts are kept in `docs/06-infrastructure/forge-01/`. Copy
`forge-backup.sh` and `forge-backup-upload.py` to `/usr/local/bin/`, both root-owned and `0700`,
recreate `/root/.forge-backup.env` at `0600` from `forge-backup.env.example` filled in with the
Doppler values, install `forge-backup.service` and `forge-backup.timer` into
`/etc/systemd/system/`, then run `systemctl daemon-reload
&& systemctl enable --now forge-backup.timer`. Prove it immediately with `systemctl start
forge-backup.service` and check `/var/log/forge-backup.log` for an `OK` line naming the object key
and byte size. The timer runs daily at 04:20 UTC with up to ten minutes of jitter and
`Persistent=true`, so a box that was down at the scheduled hour catches up on boot.

The Wasabi sub-user `forge-backup` deliberately has no `s3:DeleteObject` permission, so forge-01
cannot erase its own history. Retention pruning is therefore a separate job that must run from the
workstation or another allowed host using the account-level Wasabi key, never from forge-01.

### Do not "fix" the ownership of `/opt/forge/backups`

`stat /opt/forge/backups` reports `owner=UNKNOWN:UNKNOWN mode=700`. **That is correct, and it is
not drift.** The directory is owned `1000:1000` to match the `git` user inside the Forgejo
container, and forge-01 has no host user at uid 1000, so the name has nothing to resolve to. The
dump is taken with `docker exec -u git`, which writes into this directory through the
`./backups:/backups` bind mount; changing the owner to `root:root` to tidy up the `UNKNOWN` would
take that write permission away. The job would then stop producing backups without anyone
noticing until a restore was needed, which is the worst shape this failure can take. Leave it
alone, including when you are on the box troubleshooting something else entirely.

The steady state is small: retention keeps the two most recent archives at roughly 141 MB each,
about 283 MB on disk against 68 G free. `forge-backup.sh` prunes to that limit on the failure path
as well as on success, so a run of broken uploads cannot fill the disk.

## Restoring without a backup

Reinstall Forgejo from the compose file, complete the install wizard, create the `grotap-admin` user
from `FORGE_ADMIN_USER` and `FORGE_ADMIN_PASSWORD`, create the `Grotap-AI` organisation, then
recreate the four pull mirrors via `POST /api/v1/repos/migrate` with `mirror=true`,
`mirror_interval=10m` and `service=github`, and the webhook to
`https://api.grotap.com/api/v1/forgejo/pipeline-sync` signed with `FORGEJO_WEBHOOK_SECRET`. Mint a
new `platform-automation` token and write it to Doppler as `FORGE_API_TOKEN` in both configs. This
path loses only forge-local history, for the reason given at the top of this document.

#!/usr/bin/env bash
#
# Nightly Forgejo backup for forge-01.
#
# Produces a real `forgejo dump` (never a copy of the live sqlite file), verifies
# the archive, uploads it to Wasabi, then removes the local copy once the remote
# object has been re-read and its size confirmed.
#
# The archive contains app.ini (SECRET_KEY, INTERNAL_TOKEN, webhook secret), the
# sqlite database with password hashes and API tokens, and every repository.
# It is a credential in its own right and is kept 0600 root-owned throughout.
#
# Credentials come from /root/.forge-backup.env (root-owned, 0600). forge-01
# deliberately has no Doppler token and must not be given one.

set -euo pipefail

ENV_FILE=/root/.forge-backup.env
LOG_FILE=/var/log/forge-backup.log
UPLOADER=/usr/local/bin/forge-backup-upload.py
LOCK_FILE=/run/forge-backup.lock
KEEP_LOCAL=2

START_EPOCH=$(date -u +%s)
TS=$(date -u +%Y%m%dT%H%M%SZ)

log() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$LOG_FILE"
}

fail() {
    log "FAIL ts=$TS $*"
    exit 1
}

umask 077
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"

# Only one run at a time; the script is safe to invoke twice.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "SKIP ts=$TS reason=another_run_in_progress"
    exit 0
fi

[[ -r "$ENV_FILE" ]] || fail "missing or unreadable $ENV_FILE"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

: "${FORGE_CONTAINER:?FORGE_CONTAINER not set}"
: "${BACKUP_DIR:?BACKUP_DIR not set}"
: "${WASABI_BUCKET:?WASABI_BUCKET not set}"
: "${S3_PREFIX:=forge-01}"
FORGE_DATA_DIR=${FORGE_DATA_DIR:-/opt/forge/forgejo}

# Sanity check: the dump must never land inside the Forgejo data directory, or
# the next dump archives the previous one and we end up backing up our backups.
# The compose bind mount already places BACKUP_DIR outside the data dir; this is
# a cheap assertion that it stays that way.
case "$(readlink -f "$BACKUP_DIR")/" in
    "$(readlink -f "$FORGE_DATA_DIR")"/*)
        fail "BACKUP_DIR=$BACKUP_DIR is inside the Forgejo data dir $FORGE_DATA_DIR"
        ;;
esac

[[ -d "$BACKUP_DIR" ]] || fail "BACKUP_DIR $BACKUP_DIR does not exist"
docker inspect "$FORGE_CONTAINER" >/dev/null 2>&1 || fail "container $FORGE_CONTAINER not found"
[[ "$(docker inspect -f '{{.State.Running}}' "$FORGE_CONTAINER")" == "true" ]] \
    || fail "container $FORGE_CONTAINER is not running"

ARCHIVE_NAME="forge-${TS}.zip"
HOST_ARCHIVE="${BACKUP_DIR}/${ARCHIVE_NAME}"
CONTAINER_ARCHIVE="/backups/${ARCHIVE_NAME}"

# Forgejo runs as uid/gid 1000 (git) inside the container; the dump has to be
# taken as that user or it cannot read its own data directory.
if ! docker exec -u git "$FORGE_CONTAINER" \
        forgejo dump -c /data/gitea/conf/app.ini --file "$CONTAINER_ARCHIVE" >/dev/null 2>&1; then
    rm -f "$HOST_ARCHIVE"
    fail "forgejo dump returned non-zero"
fi

[[ -s "$HOST_ARCHIVE" ]] || fail "dump produced no archive at $HOST_ARCHIVE"
chown root:root "$HOST_ARCHIVE"
chmod 0600 "$HOST_ARCHIVE"

SIZE=$(stat -c %s "$HOST_ARCHIVE")

# Verify the archive before trusting it. forge-01 has no unzip; python3's
# zipfile does the same CRC check.
if ! python3 - "$HOST_ARCHIVE" <<'PY'
import sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path) as zf:
    bad = zf.testzip()
    if bad is not None:
        sys.exit(f"corrupt member: {bad}")
    names = zf.namelist()
if "app.ini" not in names:
    sys.exit("archive is missing app.ini")
# Forgejo 13 names the SQL dump forgejo-db.sql; older Gitea-era builds used
# gitea-db.sql. Accept either so a version bump does not break the check.
if not {"forgejo-db.sql", "gitea-db.sql"} & set(names):
    sys.exit("archive is missing the database dump (forgejo-db.sql/gitea-db.sql)")
if not any(n.startswith("repos/") for n in names):
    sys.exit("archive contains no repos/ entries")
PY
then
    fail "archive verification failed for $HOST_ARCHIVE (size=$SIZE)"
fi

OBJECT_KEY="${S3_PREFIX}/${TS:0:4}/${TS:4:2}/${ARCHIVE_NAME}"

# Keep only the newest KEEP_LOCAL archives on disk. This runs on the failure
# path too: an archive is ~140 MB, so if uploads stay broken (for example
# while the scoped Wasabi key is still a placeholder) unpruned archives would
# fill the disk in a few hundred nights and take the forge down with them.
prune_local() {
    local stale
    while IFS= read -r stale; do
        [[ -n "$stale" ]] && rm -f -- "$stale"
    done < <(ls -1t "${BACKUP_DIR}"/forge-*.zip 2>/dev/null | tail -n +$((KEEP_LOCAL + 1)))
    # A while loop returns the status of the last command in its body. A blank
    # line makes the `[[ -n ]] && rm` list return 1, which under `set -e` would
    # kill the script AFTER a successful upload -- and on the failure path would
    # exit before the FAIL lines below are logged. Pruning nothing is success.
    return 0
}

if ! UPLOAD_OUT=$(python3 "$UPLOADER" "$HOST_ARCHIVE" "$OBJECT_KEY" 2>&1); then
    prune_local
    log "FAIL ts=$TS stage=upload key=$OBJECT_KEY size=$SIZE detail=${UPLOAD_OUT//$'\n'/ | }"
    log "FAIL ts=$TS local archive retained at $HOST_ARCHIVE"
    exit 1
fi

# The upload is only trusted because the helper re-read the object and compared
# its size, so it is now safe to drop local copies beyond the newest KEEP_LOCAL.
prune_local

ELAPSED=$(( $(date -u +%s) - START_EPOCH ))
log "OK ts=$TS key=$OBJECT_KEY size=$SIZE elapsed=${ELAPSED}s local_kept=$(ls -1 "${BACKUP_DIR}"/forge-*.zip 2>/dev/null | wc -l)"
echo "OK $OBJECT_KEY size=$SIZE"

#!/bin/bash
# fleet-model-probe.sh — Can the fleet actually reach the model? Answers it directly.
#
# Why this exists: on 2026-09-15 the fleet was reported as uncapped when it was not. The
# report was true about the owner's account and false about the fleet, because the two are
# governed by different limits — the fleet key `grotap-platform` sits in the org's DEFAULT
# workspace (workspace_id null), while the named "Claude Code" workspace holds separate keys.
# Raising a limit on one is a different Console page, not a different value on the same page.
#
# That is the failure shape logged in agents/lessons/fleet-ops.md: a healthy-looking signal
# read off the wrong probe. The only check that settles "can a dispatch reach the model" is a
# real call with the key the boxes actually use. That is what this does, for one token.
#
# Usage:
#   bash fleet-model-probe.sh                 # probe using the workstation's Doppler (prd)
#   bash fleet-model-probe.sh --config dev    # probe the dev config's key
#   bash fleet-model-probe.sh --host agent-02-claude # probe with the key as that BOX resolves it
#   bash fleet-model-probe.sh --quiet         # exit status only, for cron/CI use
#   FLEET_PROBE_MODEL=<id> bash fleet-model-probe.sh    # override the pinned model
#
# Exit status — five distinct states, because they need five different actions:
#   0  PASS         the key reached the model. Dispatch is not blocked.
#   1  CAPPED       a configured spend limit. Owner action in the Console. EXPECTED for now.
#   2  UNREACHABLE  the probe could not run at all (no Doppler, no network, host down).
#   3  AUTH         401/403 — the key is bad, revoked or rotated. NOT a cap.
#   4  RATE-LIMITED 429 — transient. Retry. NOT a cap and NOT a spend problem.
#   5  FAIL         any other API error. UNEXPECTED — alert on this one. Sharing an exit
#                   code with CAPPED would let a real upstream fault hide inside the state
#                   callers are told to tolerate, which defeats the point of this script.
#
# NOTE FOR CALLERS: a non-zero exit is the EXPECTED state while a cap is in force. If you
# call this from a cron or a wrapper, do not let its exit status fail your job — read the
# code and decide. A probe that takes down its caller when the answer is "capped" just moves
# the problem somewhere new.
# `-e` is DELIBERATELY OMITTED. This script is full of bare `[[ -n ... ]] && say` guards, and
# under `set -e` a false condition makes the script exit with status 1 — which is CAPPED's code.
# A probe that failed to read its own key would then report a spend cap. That is the same defect
# that bit prune_local in forge-backup.sh, one letter away. Do not "harden" this line.
set -uo pipefail

CONFIG="prd"
REMOTE_HOST=""
QUIET=0
MODEL="${FLEET_PROBE_MODEL:-claude-haiku-4-5-20251001}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="${2:?--config needs a value}"; shift 2 ;;
    --host)   REMOTE_HOST="${2:?--host needs a value}"; shift 2 ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$*"; }

# The smallest call that still exercises the limit: cheapest model, 1 output token.
# Deliberately NOT a models-list or a key-validity call — those SUCCEED while capped, which
# is exactly the wrong-probe mistake this script exists to prevent.
#
# It also prints a sha256 prefix of the resolved key, never the key. A claim about capability
# has to say which credential it is a claim about; that was the whole defect on 2026-09-15.
read -r -d '' PROBE_CMD <<INNER || true
printf 'keyfp=%s\n' "\$(printf '%s' "\$ANTHROPIC_API_KEY" | sha256sum | cut -c1-16)"
curl -s --max-time 20 -o /tmp/fmp.\$\$.json -w 'code=%{http_code}\n' \
  https://api.anthropic.com/v1/messages \
  -H "x-api-key: \$ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"${MODEL}","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
cat /tmp/fmp.\$\$.json 2>/dev/null
rm -f /tmp/fmp.\$\$.json
INNER

if [[ -n "$REMOTE_HOST" ]]; then
  say "probe: $REMOTE_HOST (key as that box resolves it), model $MODEL"
  # StrictHostKeyChecking=yes — fail closed. --host takes a bare IP as readily as an
  # alias, and a bare IP resolves through the catch-all glob in ~/.ssh/config, which
  # carries "StrictHostKeyChecking no". This probe runs a command on the far end and
  # reads a key fingerprint back, so an unverified destination is the wrong place to
  # be relaxed. The exposure is unauthenticated-destination command execution, NOT
  # key disclosure: offering public-key auth does not hand over the private half.
  # THIS ALONE DOES NOT CLOSE THE HOLE — the ~/.ssh/config globs are the actual
  # mitigation and are owned by another session; this removes one automated rider.
  # SEEDING REQUIRED: known_hosts must hold a correct entry for every fleet address
  # used here. As of 2026-09-15 four fleet IPs present ed25519 keys that MISMATCH
  # known_hosts; a mismatch is a refusal, not a first-contact prompt, so those four
  # fail immediately under this setting.
  OUT=$(ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=yes "$REMOTE_HOST" \
        "su - agent -c 'doppler run -- bash -s' <<'EOF'
$PROBE_CMD
EOF" 2>&1) || {
    # Exit 2 covers "the probe could not run", but the REASON changes who fixes it: a network or
    # SSH failure is an infrastructure problem, a Doppler failure is a bad or expired service
    # token on that box. Same exit code, because the caller's action is identical (the probe told
    # you nothing) — different message, because the human's next step is not.
    if printf '%s' "$OUT" | grep -qi 'doppler'; then
      say "UNREACHABLE  Doppler failed on $REMOTE_HOST — a CONFIG fault on the box (bad or"
      say "             expired service token), NOT a network problem:"
    else
      say "UNREACHABLE  could not reach or run on $REMOTE_HOST:"
    fi
    say "$(printf '%s' "$OUT" | tail -3)"
    exit 2
  }
else
  say "probe: workstation Doppler, grotap/$CONFIG, model $MODEL"
  OUT=$(doppler run -p grotap -c "$CONFIG" -- bash -c "$PROBE_CMD" 2>&1) \
    || { say "UNREACHABLE  doppler or curl could not run:"; say "$(printf '%s' "$OUT" | tail -3)"; exit 2; }
fi

KEYFP=$(printf '%s' "$OUT" | sed -n 's/^keyfp=//p' | head -1)
CODE=$(printf '%s' "$OUT" | sed -n 's/^code=//p' | head -1 | tr -dc '0-9')
BODY=$(printf '%s' "$OUT" | grep -v '^keyfp=' | grep -v '^code=')
[[ -n "$KEYFP" ]] && say "key sha256: ${KEYFP}  (fingerprint only — never the key itself)"

if [[ -z "$CODE" ]]; then
  say "UNREACHABLE  no HTTP status came back; the call did not complete."
  exit 2
fi

MSG=$(printf '%s' "$BODY" | python -c 'import sys,json
try:
    print(json.load(sys.stdin)["error"]["message"])
except Exception:
    pass' 2>/dev/null)
[[ -z "$MSG" ]] && MSG=$(printf '%s' "$BODY" | head -c 200)

case "$CODE" in
  000)
    # curl still prints code=000 when it never established a connection (DNS, TLS, timeout),
    # and it does so with a zero exit from the wrapper, so this does NOT trip the guards
    # above. Without this branch a network outage reports as an uncategorized API FAIL and
    # pages the wrong person.
    say "UNREACHABLE  curl could not establish a connection (DNS, TLS or timeout)."
    [[ -n "$MSG" ]] && say "             $MSG"
    exit 2 ;;
  200)
    say "PASS         HTTP 200 — this key reached the model. Dispatch is not blocked by a cap."
    exit 0 ;;
  401|403)
    say "AUTH         HTTP $CODE — $MSG"
    say "The key is bad, revoked or rotated. This is NOT a spend cap — do not wait for a reset date."
    exit 3 ;;
  429)
    say "RATE-LIMITED HTTP 429 — $MSG"
    say "Transient. Retry shortly. NOT a spend cap and NOT an owner action."
    exit 4 ;;
esac

if [[ "$MSG" == *"usage limits"* ]]; then
  # Read the regain date off the RESPONSE, never off a local constant — a second hardcoded
  # copy would drift out of sync with USAGE_CAP_UNTIL in fleet-load.sh.
  WHEN=$(printf '%s' "$MSG" | sed -n 's/.*regain access on \(.*\)\.\?$/\1/p')
  say "CAPPED       HTTP $CODE — configured spend limit reached."
  [[ -n "$WHEN" ]] && say "             regain access: $WHEN   (read from the API, not from a constant)"
  say ""
  say "This is a CONFIGURED SPEND LIMIT — not empty credits, not a code fault, not a bad key."
  say "The fleet key is 'grotap-platform', which sits in the org's DEFAULT workspace."
  say "Raising a limit on the named 'Claude Code' workspace does NOT lift this one."
  exit 1
fi

# Deliberately NOT exit 1: callers are told to tolerate CAPPED, so an uncategorized failure
# must not wear its exit code. This is the state that deserves an alert.
say "FAIL         HTTP $CODE — $MSG"
say "             Uncategorized failure — this is NOT the expected cap. Investigate."
exit 5

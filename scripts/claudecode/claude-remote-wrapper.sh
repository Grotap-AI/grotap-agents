#!/usr/bin/env bash
# claude-remote-wrapper.sh — Per-user Claude Code Remote Control launcher.
#
# Runs AS the user (ExecStart in a systemd user unit).
# 1. git-pulls ~/workspace/grotap (best-effort; network failures do not abort).
# 2. Sources .claude-session-init.sh from the workspace root (best-effort).
# 3. Streams claude remote-control output:
#    - tees every line to ~/.claude-remote/current.log
#    - writes the first https:// URL found to ~/.claude-remote/url
#      (mode 0640, group status-agent, timestamp updated via touch)
#    - passes all output to stdout for journald capture
#
# No deadlock guarantee: stdbuf -oL forces line-buffered output at every
# pipeline stage so lines are not held until a pipe buffer fills.
# URL extraction uses a pass-through read loop (no named pipe or background
# reader) — the read end is never closed early, so tee cannot get SIGPIPE.
set -euo pipefail

LABEL="${CLAUDE_REMOTE_LABEL:-${USER:-default}}"
WORKSPACE="${HOME}/workspace/grotap"
LOG_DIR="${HOME}/.claude-remote"
LOG_FILE="${LOG_DIR}/current.log"
URL_FILE="${LOG_DIR}/url"

# Rapid-exit tracking: persist a counter across restarts; archive wedged state
# when it reaches RAPID_EXIT_SECS_THRESHOLD consecutive rapid exits.
RAPID_EXIT_SECS="${RAPID_EXIT_SECS:-30}"
RAPID_EXIT_FILE="${LOG_DIR}/rapid-exits"
RESUME_STATE_DIR="${HOME}/.claude/projects/-home-${USER}-workspace-grotap"

mkdir -p "${LOG_DIR}"

# --------------------------------------------------------------------------
# 0. Seat probe — run once on start (timer fires every 5 min for subsequent
#    checks).  Best-effort: a missing or broken probe must never abort the
#    session.  Output goes to journald via the wrapper's stdout/stderr.
# --------------------------------------------------------------------------
_PROBE="${HOME}/workspace/grotap/platform/scripts/claudecode/seat-probe.sh"
if [[ -x "${_PROBE}" ]]; then
    "${_PROBE}" &
fi
unset _PROBE

# --------------------------------------------------------------------------
# 1. Update workspace (network / git failures must not abort the session).
# Sanitize git error output so credential-embedded URLs never reach stdout,
# the log file, or journald (pattern: https://user:token@host).
# --------------------------------------------------------------------------
_sanitize_url() { printf '%s' "$*" | sed 's|://[^:@/ ]*:[^@]*@|://[REDACTED]@|g; s|://[^:@/ ]*@|://[REDACTED]@|g'; }
_pull_err="$(mktemp)"
git -C "${WORKSPACE}" pull --ff-only 2>"${_pull_err}" || \
  printf '[workspace-sync] %s\n' "$(_sanitize_url "$(cat "${_pull_err}")")" >&2
rm -f "${_pull_err}"
unset _pull_err
_pull_err="$(mktemp)"
git -C "${WORKSPACE}/platform" pull --ff-only 2>"${_pull_err}" || \
  printf '[workspace-sync/platform] %s\n' "$(_sanitize_url "$(cat "${_pull_err}")")" >&2
rm -f "${_pull_err}"
unset _pull_err

# --------------------------------------------------------------------------
# 2. Source session init from workspace root (best-effort; errors are noise).
# --------------------------------------------------------------------------
cd "${WORKSPACE}"
# shellcheck source=/dev/null
source ./.claude-session-init.sh 2>/dev/null || true

# --------------------------------------------------------------------------
# 3. URL extractor: pass every line to stdout; on the first https:// URL,
#    write it atomically to ~/.claude-remote/url (0640, group=status-agent).
#    Uses a flag (never breaks out of the loop) so the read end of the pipe
#    stays open — tee can write without hitting SIGPIPE.
# --------------------------------------------------------------------------
_extract_url() {
    local url_found=false
    while IFS= read -r line; do
        printf '%s\n' "${line}"
        if ! "${url_found}" && [[ "${line}" =~ (https://[[:graph:]]+) ]]; then
            local url="${BASH_REMATCH[1]}"
            local tmp
            tmp="$(mktemp "${LOG_DIR}/.url.XXXXXX")"
            printf '%s\n' "${url}" >"${tmp}"
            chmod 0640 "${tmp}"
            chgrp status-agent "${tmp}" 2>/dev/null || true
            mv "${tmp}" "${URL_FILE}"
            touch "${URL_FILE}"
            url_found=true
        fi
    done
}

# --------------------------------------------------------------------------
# 4. Rapid-exit detection and wedged-session recovery.
#    If claude exits in under RAPID_EXIT_SECS seconds, increment the counter
#    at RAPID_EXIT_FILE; reset to 0 on runs that survive longer.
#    When the counter is >= 2 at the start of a run: mv the session resume
#    state dir to a timestamped backup (never rm), log a single WARN line,
#    reset the counter, and use the fresh-session path (skip --continue).
# --------------------------------------------------------------------------
_get_rapid_count() { cat "${RAPID_EXIT_FILE}" 2>/dev/null || printf '0'; }

_rapid_count="$(_get_rapid_count)"
_use_continue=true

if [[ "${_rapid_count}" -ge 2 ]]; then
    _backup="${HOME}/.claude/wedged-session-backup-$(date +%Y%m%d-%H%M%S)"
    if [[ -d "${RESUME_STATE_DIR}" ]]; then
        mv "${RESUME_STATE_DIR}" "${_backup}"
    fi
    printf '[rapid-exit] WARN: %d consecutive rapid exits detected; archived resume state to %s; starting fresh session\n' \
        "${_rapid_count}" "${_backup}" >&2
    printf '0\n' >"${RAPID_EXIT_FILE}"
    _use_continue=false
fi

# --------------------------------------------------------------------------
# 5. Run claude remote-control.  --continue reconnects an existing session;
#    fall back to a fresh start if --continue is not recognised or fails.
#    stdbuf -oL forces line-buffered stdout at every pipeline stage.
#    stdin gets "y" — the CLI asks "Enable Remote Control? (y/n)" on EVERY
#    start (not persisted), and under systemd there is no TTY to answer it.
#    --permission-mode bypassPermissions: browser sessions must not prompt
#    for tool approval (owner directive 2026-07-09) — same effect as the
#    fleet's --dangerously-skip-permissions, which remote-control rejects.
#
# PLAYWRIGHT_BROWSERS_PATH: systemd user units do not source /etc/profile.d,
# so the global playwright.sh profile drop-in is invisible here.  Export
# explicitly so claude's Playwright E2E tests find the shared /opt/playwright
# browser install rather than downloading per-seat copies.
# --------------------------------------------------------------------------
export PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
_start_epoch="$(date +%s)"
_claude_rc=0

(
    if [[ "${_use_continue}" == "true" ]]; then
        printf 'y\n' | stdbuf -oL claude remote-control --permission-mode bypassPermissions --name "grotap-${LABEL}" --continue 2>&1 \
            || printf 'y\n' | stdbuf -oL claude remote-control --permission-mode bypassPermissions --name "grotap-${LABEL}" 2>&1
    else
        printf 'y\n' | stdbuf -oL claude remote-control --permission-mode bypassPermissions --name "grotap-${LABEL}" 2>&1
    fi
) | stdbuf -oL tee "${LOG_FILE}" | _extract_url || _claude_rc=$?

_end_epoch="$(date +%s)"
_elapsed=$(( _end_epoch - _start_epoch ))
if [[ "${_elapsed}" -lt "${RAPID_EXIT_SECS}" ]]; then
    _prev_count="$(_get_rapid_count)"
    _new_count=$(( _prev_count + 1 ))
    printf '%d\n' "${_new_count}" >"${RAPID_EXIT_FILE}"
else
    printf '0\n' >"${RAPID_EXIT_FILE}"
fi

exit "${_claude_rc}"

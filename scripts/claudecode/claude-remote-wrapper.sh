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

mkdir -p "${LOG_DIR}"

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
# 4. Run claude remote-control.  --continue reconnects an existing session;
#    fall back to a fresh start if --continue is not recognised or fails.
#    stdbuf -oL forces line-buffered stdout at every pipeline stage.
#    stdin gets "y" — the CLI asks "Enable Remote Control? (y/n)" on EVERY
#    start (not persisted), and under systemd there is no TTY to answer it.
#    --permission-mode bypassPermissions: browser sessions must not prompt
#    for tool approval (owner directive 2026-07-09) — same effect as the
#    fleet's --dangerously-skip-permissions, which remote-control rejects.
# --------------------------------------------------------------------------
(
    printf 'y\n' | stdbuf -oL claude remote-control --permission-mode bypassPermissions --name "grotap-${LABEL}" --continue 2>&1 \
        || printf 'y\n' | stdbuf -oL claude remote-control --permission-mode bypassPermissions --name "grotap-${LABEL}" 2>&1
) | stdbuf -oL tee "${LOG_FILE}" | _extract_url

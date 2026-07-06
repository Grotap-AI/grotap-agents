#!/usr/bin/env bash
# ensure-swap.sh — Idempotent 4 GiB swap file setup for grotap agent servers.
# CANONICAL COPY (single source of truth). A synced mirror lives in grotap-platform
# at platform/agents/ensure-swap.sh (used by agents/setup-server.sh); keep both in sync.
# Safe to run multiple times; a second run on an already-configured host is a no-op.
# Requires: root privileges, ≥6 GiB free disk space on /.

set -euo pipefail

SWAPFILE="/swapfile"
FSTAB_ENTRY="/swapfile swap swap defaults 0 0"
SYSCTL_CONF="/etc/sysctl.d/99-grotap-swap.conf"
SWAPPINESS=10
MIN_FREE_KB=$(( 6 * 1024 * 1024 ))   # 6 GiB expressed in 1K blocks
readonly SWAPFILE FSTAB_ENTRY SYSCTL_CONF SWAPPINESS MIN_FREE_KB

# ── helpers ─────────────────────────────────────────────────────────────────

log() { echo "[ensure-swap] $*"; }

ensure_fstab() {
    if grep -qxF "${FSTAB_ENTRY}" /etc/fstab; then
        log "fstab entry already present."
    else
        echo "${FSTAB_ENTRY}" >> /etc/fstab
        log "fstab entry added."
    fi
}

ensure_sysctl() {
    echo "vm.swappiness=${SWAPPINESS}" > "${SYSCTL_CONF}"
    sysctl -p "${SYSCTL_CONF}" > /dev/null
    log "vm.swappiness=${SWAPPINESS} applied."
}

# ── pre-flight checks ────────────────────────────────────────────────────────

if [[ "$(id -u)" -ne 0 ]]; then
    log "Must be run as root. Try: sudo $0"
    exit 1
fi

free_kb=$(df --output=avail / | tail -1)
if [[ "${free_kb}" -lt "${MIN_FREE_KB}" ]]; then
    log "Only ${free_kb} KB free on /; need at least ${MIN_FREE_KB} KB (6 GiB). Skipping swap setup."
    exit 0
fi

# ── idempotency: detect active swap ─────────────────────────────────────────
# If any swap is already active, only ensure fstab + sysctl are in sync.

active_swap=$(swapon --show --noheadings 2>/dev/null || true)
if [[ -n "${active_swap}" ]]; then
    log "Swap already active — ensuring fstab entry and sysctl config only."
    ensure_fstab
    ensure_sysctl
    log "Done (no-op run)."
    exit 0
fi

# ── create swap file ─────────────────────────────────────────────────────────

log "No active swap found. Creating ${SWAPFILE} (4 GiB)..."

if ! fallocate -l 4G "${SWAPFILE}" 2>/dev/null; then
    log "fallocate unavailable or failed; falling back to dd (this may take a while)..."
    dd if=/dev/zero of="${SWAPFILE}" bs=1M count=4096
fi

chmod 600 "${SWAPFILE}"
mkswap "${SWAPFILE}"
swapon "${SWAPFILE}"
log "Swap file created and activated."

ensure_fstab
ensure_sysctl

log "Done."

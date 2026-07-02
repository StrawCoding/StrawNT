#!/usr/bin/env bash
# build-iso.sh — Repack cloned Ubuntu rootfs into StrawWU live ISO.
#
# Phase 1: validates clone pipeline; full xorriso repack is stubbed until
# casper metadata from source ISO is wired (tracked in Phase 1.3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
OUTPUT_DIR="${REPO_ROOT}/os-image/output"
VERSION="${STRAWWU_VERSION:-2.0.0-reboot}"
ISO_NAME="StrawWU-${VERSION}-amd64.iso"
ISO_PATH="${OUTPUT_DIR}/${ISO_NAME}"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

main() {
    [[ -f "${WORK_DIR}/.clone-ubuntu-base-ok" ]] || die "run make clone-ubuntu-base first"
    bash "${SCRIPT_DIR}/swap-kernel.sh"

    mkdir -p "${OUTPUT_DIR}"

    # Phase 1 stub: record rootfs manifest as build artifact until xorriso repack lands.
    local manifest="${OUTPUT_DIR}/StrawWU-${VERSION}-rootfs-manifest.txt"
    log "writing manifest (Phase 1 stub — full ISO repack in Phase 1.3)"
    {
        echo "version=${VERSION}"
        echo "built=$(date -Is)"
        echo "rootfs=${ROOTFS_DIR}"
        echo "kernel_marker=$(cat "${WORK_DIR}/.swap-kernel-ok" 2>/dev/null || echo unknown)"
        echo "--- packages (sample) ---"
        chroot "${ROOTFS_DIR}" dpkg -l 2>/dev/null | grep -E 'linux-image|calamares' | head -20 || true
    } > "${manifest}"

    if command -v xorriso >/dev/null 2>&1 && [[ "${STRAWWU_ISO_FULL:-0}" == "1" ]]; then
        die "STRAWWU_ISO_FULL=1 repack not yet implemented — see docs/architecture.md Phase 1.3"
    fi

    # Touch placeholder ISO path for Makefile target wiring
    echo "Phase 1 stub — run with STRAWWU_ISO_FULL=1 after Phase 1.3 implementation" > "${ISO_PATH}.stub"
    sha256sum "${manifest}" | tee "${manifest}.sha256"
    log "build stub complete: ${manifest}"
}

main "$@"

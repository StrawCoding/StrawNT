#!/usr/bin/env bash
# repack-initrd-branding.sh — inject StrawWU Plymouth theme into casper initrd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BRANDING_DIR="${REPO_ROOT}/os-image/config/branding"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ISO_STAGING="${WORK_DIR}/iso-staging"
INITRD="${ISO_STAGING}/casper/initrd"
THEME_SRC="${BRANDING_DIR}/usr/share/plymouth/themes/strawwu-boot"
PLYMOUTH_CONF="${BRANDING_DIR}/etc/plymouth/plymouthd.conf"
SPLICE="${SCRIPT_DIR}/initrd-splice.py"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

repack_initrd() {
    local initrd_in="$1"
    local initrd_out="$2"
    local scratch="${WORK_DIR}/initrd-repack"
    local target

    [[ -f "${initrd_in}" ]] || die "initrd missing: ${initrd_in}"
    [[ -d "${THEME_SRC}" ]] || die "plymouth theme missing: ${THEME_SRC}"
    [[ -f "${SPLICE}" ]] || die "initrd splice helper missing: ${SPLICE}"

    rm -rf "${scratch}"
    mkdir -p "${scratch}"
    log "extracting initrd with unmkinitramfs"
    unmkinitramfs "${initrd_in}" "${scratch}"

    target="${scratch}/main"
    [[ -d "${target}" ]] || die "initrd main/ missing after extract"

    log "injecting strawwu-boot plymouth theme into initrd main/"
    mkdir -p "${target}/usr/share/plymouth/themes/strawwu-boot"
    cp -a "${THEME_SRC}/." "${target}/usr/share/plymouth/themes/strawwu-boot/"
    mkdir -p "${target}/etc/plymouth"
    cp -a "${PLYMOUTH_CONF}" "${target}/etc/plymouth/plymouthd.conf"
    ln -sf /usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth \
        "${target}/usr/share/plymouth/themes/default.plymouth"

    if [[ -f "${target}/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth" ]]; then
        sed -i 's/^title=.*/title=StrawWU/' \
            "${target}/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth" || true
    fi

    log "repacking initrd (preserve early phases, zstd main only)"
    python3 "${SPLICE}" repack-main-only "${initrd_in}" "${target}" "${initrd_out}" "${scratch}/splice"
    python3 "${SPLICE}" verify "${initrd_out}" >&2 || die "initrd verify failed after branding repack"
    log "initrd repack complete: ${initrd_out} ($(du -h "${initrd_out}" | cut -f1))"
}

main() {
    [[ -f "${INITRD}" ]] || die "casper initrd not staged: ${INITRD}"
    local backup="${INITRD}.ubuntu-backup"
    if [[ ! -f "${backup}" ]]; then
        cp -a "${INITRD}" "${backup}"
    fi
    repack_initrd "${backup}" "${INITRD}"
}

main "$@"

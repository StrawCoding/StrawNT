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

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

repack_initrd() {
    local initrd_in="$1"
    local initrd_out="$2"
    local scratch="${WORK_DIR}/initrd-repack"
    local phase cpio_out

    [[ -f "${initrd_in}" ]] || die "initrd missing: ${initrd_in}"
    [[ -d "${THEME_SRC}" ]] || die "plymouth theme missing: ${THEME_SRC}"

    rm -rf "${scratch}"
    mkdir -p "${scratch}"
    log "extracting initrd with unmkinitramfs"
    unmkinitramfs "${initrd_in}" "${scratch}"

    local target="${scratch}/main"
    [[ -d "${target}" ]] || die "initrd main/ missing after extract"

    log "injecting strawwu-boot plymouth theme into initrd main/"
    mkdir -p "${target}/usr/share/plymouth/themes/strawwu-boot"
    cp -a "${THEME_SRC}/." "${target}/usr/share/plymouth/themes/strawwu-boot/"
    mkdir -p "${target}/etc/plymouth"
    cp -a "${PLYMOUTH_CONF}" "${target}/etc/plymouth/plymouthd.conf"
    ln -sf /usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth \
        "${target}/usr/share/plymouth/themes/default.plymouth"

    # Replace ubuntu-text title if present (fallback path).
    if [[ -f "${target}/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth" ]]; then
        sed -i 's/^title=.*/title=StrawWU/' \
            "${target}/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth" || true
    fi

    log "repacking initrd phases"
    : > "${initrd_out}.partial"
    for phase in early early2 early3 main; do
        [[ -d "${scratch}/${phase}" ]] || continue
        cpio_out="${scratch}/${phase}.cpio"
        (cd "${scratch}/${phase}" && find . -print0 | cpio --null -o --format=newc --quiet) > "${cpio_out}"
        cat "${cpio_out}" >> "${initrd_out}.partial"
    done
    mv "${initrd_out}.partial" "${initrd_out}"
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

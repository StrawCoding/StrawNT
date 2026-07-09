#!/usr/bin/env bash
# swap-kernel.sh — Replace Ubuntu generic kernel with StrawWU custom kernel in cloned rootfs.
#
# Phase 1: if STRAWWU_KERNEL_DEB unset, keep Ubuntu kernel (noop + marker).
# Phase 2+: install linux-image-strawwu_*.deb and purge linux-image-generic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/base-marker.sh
source "${SCRIPT_DIR}/lib/base-marker.sh"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${ROOTFS_DIR:-${WORK_DIR}/rootfs}"
MARKER="${WORK_DIR}/.swap-kernel-ok"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

unmount_chroot() {
    umount "${ROOTFS_DIR}/run" 2>/dev/null || umount -l "${ROOTFS_DIR}/run" 2>/dev/null || true
    umount "${ROOTFS_DIR}/sys" 2>/dev/null || umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
    umount "${ROOTFS_DIR}/proc" 2>/dev/null || umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
    umount "${ROOTFS_DIR}/dev" 2>/dev/null || umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
}

chroot_run() {
    mount --bind /dev  "${ROOTFS_DIR}/dev"
    mount --bind /proc "${ROOTFS_DIR}/proc"
    mount --bind /sys  "${ROOTFS_DIR}/sys"
    mount --bind /run  "${ROOTFS_DIR}/run" 2>/dev/null || true
    trap 'unmount_chroot' EXIT
    chroot "${ROOTFS_DIR}" "$@"
    local rc=$?
    unmount_chroot
    trap - EXIT
    return "${rc}"
}

main() {
    die_unless_base_marker "${WORK_DIR}"
    [[ -d "${ROOTFS_DIR}" ]] || die "rootfs missing: ${ROOTFS_DIR}"
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root"

    local kernel_deb="${STRAWWU_KERNEL_DEB:-}"
    if [[ -z "${kernel_deb}" ]]; then
        log "STRAWWU_KERNEL_DEB unset — keeping Ubuntu kernel (Phase 1 pipeline test)"
        echo "ubuntu-generic-kept" > "${MARKER}"
        exit 0
    fi
    [[ -f "${kernel_deb}" ]] || die "kernel deb not found: ${kernel_deb}"

    log "installing ${kernel_deb}"
    mkdir -p "${ROOTFS_DIR}/tmp"
    cp "${kernel_deb}" "${ROOTFS_DIR}/tmp/strawwu-kernel.deb"
    if ! chroot_run bash -c 'DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y /tmp/strawwu-kernel.deb'; then
        log "apt install failed (broken deps?) — falling back to dpkg -i"
        chroot_run bash -c 'DEBIAN_FRONTEND=noninteractive dpkg -i --force-depends /tmp/strawwu-kernel.deb || dpkg -i /tmp/strawwu-kernel.deb'
    fi
    # Keep the Canonical-signed concrete generic kernel + modules as the Secure Boot
    # fallback (no-MOK path). Only the generic meta-packages are purged; the actual
    # linux-image-<ver>-generic must survive autoremove.
    chroot_run bash -c '
        set -e
        for pkg in $(dpkg-query -W -f="\${Package}\n" "linux-image-*-generic" "linux-modules-*-generic" 2>/dev/null); do
            apt-mark manual "$pkg" 2>/dev/null || true
        done
        apt-get purge -y "linux-image-generic" "linux-image-generic-hwe-*" "linux-image-unsigned-*" 2>/dev/null || true
        update-initramfs -u -k all
    ' || true
    rm -f "${ROOTFS_DIR}/tmp/strawwu-kernel.deb"

    local kver=""
    kver="$(ls "${ROOTFS_DIR}/lib/modules" 2>/dev/null | grep strawwu | head -1 || true)"
    [[ -n "${kver}" ]] || kver="$(ls "${ROOTFS_DIR}/boot/vmlinuz-"* 2>/dev/null | sed 's|.*/vmlinuz-||' | head -1 || true)"

    # Secure Boot: sign the custom (unsigned) StrawWU kernel with the StrawWU MOK so
    # it boots under Secure Boot once the user enrolls the MOK. The Canonical-signed
    # generic kernel is kept in the rootfs as the no-MOK fallback (see build-iso.sh).
    local custom_vmlinuz
    custom_vmlinuz="$(ls "${ROOTFS_DIR}/boot/vmlinuz-"*strawwu* 2>/dev/null | head -1 || true)"
    if [[ -n "${custom_vmlinuz}" ]]; then
        bash "${SCRIPT_DIR}/secureboot-route/mok-sign.sh" "${custom_vmlinuz}" || true
    fi

    echo "strawwu-kernel:${kver:-unknown}" > "${MARKER}"
    log "kernel swap complete (${kver:-unknown})"
}

main "$@"

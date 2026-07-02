#!/usr/bin/env bash
# swap-kernel.sh — Replace Ubuntu generic kernel with StrawWU custom kernel in cloned rootfs.
#
# Phase 1: if STRAWWU_KERNEL_DEB unset, keep Ubuntu kernel (noop + marker).
# Phase 2+: install linux-image-strawwu_*.deb and purge linux-image-generic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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
    [[ -d "${ROOTFS_DIR}" ]] || die "rootfs missing; run clone-ubuntu-base.sh first"
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root"

    local kernel_deb="${STRAWWU_KERNEL_DEB:-}"
    if [[ -z "${kernel_deb}" ]]; then
        log "STRAWWU_KERNEL_DEB unset — keeping Ubuntu kernel (Phase 1 pipeline test)"
        echo "ubuntu-generic-kept" > "${MARKER}"
        exit 0
    fi
    [[ -f "${kernel_deb}" ]] || die "kernel deb not found: ${kernel_deb}"

    log "installing ${kernel_deb}"
    cp "${kernel_deb}" "${ROOTFS_DIR}/tmp/strawwu-kernel.deb"
    chroot_run bash -c 'DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y /tmp/strawwu-kernel.deb && apt-get purge -y "linux-image-generic*" || true && update-initramfs -u -k all'
    rm -f "${ROOTFS_DIR}/tmp/strawwu-kernel.deb"

    date -Is > "${MARKER}"
    log "kernel swap complete"
}

main "$@"

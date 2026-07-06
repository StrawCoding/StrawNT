#!/usr/bin/env bash
# fork-apply-manifest.sh — Apply fork package lists to rootfs chroot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FORK_BASE="${REPO_ROOT}/os-image/fork-base"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root"
}

chroot_run() {
    mount -t proc proc "${ROOTFS_DIR}/proc" 2>/dev/null || true
    mount -t sysfs sys "${ROOTFS_DIR}/sys" 2>/dev/null || true
    mount --bind /dev "${ROOTFS_DIR}/dev" 2>/dev/null || true
    mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    chroot "${ROOTFS_DIR}" "$@"
}

apply_remove() {
    local f="${FORK_BASE}/packages/remove.txt"
    [[ -f "${f}" ]] || return 0
    local pkgs=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | xargs)"
        [[ -n "${line}" ]] && pkgs+=("${line}")
    done < "${f}"
    if ((${#pkgs[@]})); then
        log "purging fork remove list: ${#pkgs[@]} packages"
        chroot_run apt-get purge -y "${pkgs[@]}" 2>/dev/null || true
        chroot_run apt-get autoremove -y 2>/dev/null || true
    fi
}

apply_include() {
    local f="${FORK_BASE}/packages/include.txt"
    [[ -f "${f}" ]] || return 0
    local pkgs=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | xargs)"
        [[ -n "${line}" ]] && pkgs+=("${line}")
    done < "${f}"
    if ((${#pkgs[@]})); then
        log "installing fork include list: ${#pkgs[@]} packages"
        chroot_run apt-get update -qq 2>/dev/null || true
        chroot_run apt-get install -y --no-install-recommends "${pkgs[@]}" 2>/dev/null || true
    fi
}

apply_overrides() {
    local src="${FORK_BASE}/overrides"
    [[ -d "${src}" ]] || return 0
    log "copying fork overrides"
    cp -a "${src}/." "${ROOTFS_DIR}/"
}

main() {
    need_root
    [[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing"
    apply_remove
    apply_include
    apply_overrides
    date -Is > "${WORK_DIR}/.fork-apply-manifest-ok"
    log "fork manifest applied"
}

main "$@"

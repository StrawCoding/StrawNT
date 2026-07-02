#!/usr/bin/env bash
# clone-ubuntu-base.sh — Extract Ubuntu noble desktop live rootfs from official ISO.
#
# Reference: Ubuntu live ISO casper/filesystem.squashfs structure.
# Do NOT debootstrap from scratch — clone upstream as-is.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
OUTPUT_DIR="${REPO_ROOT}/os-image/output"
ISO_CACHE="${OUTPUT_DIR}/cache"

UBUNTU_VERSION="${STRAWWU_UBUNTU_VERSION:-24.04.2}"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
UBUNTU_MIRROR="${STRAWWU_UBUNTU_MIRROR:-https://releases.ubuntu.com/${UBUNTU_VERSION%%.*}}"
ISO_URL="${UBUNTU_MIRROR}/${UBUNTU_ISO_NAME}"

ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
ISO_MOUNT="${WORK_DIR}/iso-mount"
MARKER="${WORK_DIR}/.clone-ubuntu-base-ok"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (mount/squashfs/chroot)"
}

need_cmd() {
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c"; done
}

download_iso() {
    mkdir -p "${ISO_CACHE}"
    local iso="${ISO_CACHE}/${UBUNTU_ISO_NAME}"
    if [[ -f "${iso}" ]]; then
        log "using cached ISO: ${iso}"
        echo "${iso}"
        return
    fi
    log "downloading ${ISO_URL}"
    if command -v wget >/dev/null 2>&1; then
        wget -c -O "${iso}.partial" "${ISO_URL}"
        mv "${iso}.partial" "${iso}"
    elif command -v curl >/dev/null 2>&1; then
        curl -fL -C - -o "${iso}.partial" "${ISO_URL}"
        mv "${iso}.partial" "${iso}"
    else
        die "need wget or curl"
    fi
    echo "${iso}"
}

extract_squashfs() {
    local iso="$1"
    mkdir -p "${ISO_MOUNT}" "${SQUASH_SRC}"
    if mountpoint -q "${ISO_MOUNT}" 2>/dev/null; then
        umount "${ISO_MOUNT}" || true
    fi
    mount -o loop,ro "${iso}" "${ISO_MOUNT}"
    trap 'umount "${ISO_MOUNT}" 2>/dev/null || true' EXIT

    local squashfs=""
    for candidate in \
        "${ISO_MOUNT}/casper/filesystem.squashfs" \
        "${ISO_MOUNT}/live/filesystem.squashfs"; do
        if [[ -f "${candidate}" ]]; then
            squashfs="${candidate}"
            break
        fi
    done
    [[ -n "${squashfs}" ]] || die "filesystem.squashfs not found in ISO"

    log "unsquashfs ${squashfs}"
    rm -rf "${SQUASH_SRC}"
    unsquashfs -force -d "${SQUASH_SRC}" "${squashfs}"
}

prepare_rootfs() {
    rm -rf "${ROOTFS_DIR}"
    cp -a "${SQUASH_SRC}" "${ROOTFS_DIR}"

  # Bind mounts for chroot operations later
    mkdir -p "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run"
}

verify_rootfs() {
    log "verifying Ubuntu packages in rootfs"
    local required=(
        "/etc/os-release"
        "/usr/bin/calamares"
        "/usr/share/calamares/settings-ubuntu.conf"
    )
    for f in "${required[@]}"; do
        [[ -e "${ROOTFS_DIR}${f}" ]] || die "missing in rootfs: ${f}"
    done
    if ! grep -qi 'ubuntu' "${ROOTFS_DIR}/etc/os-release"; then
        die "/etc/os-release does not look like Ubuntu"
    fi
    log "rootfs OK: $(. "${ROOTFS_DIR}/etc/os-release"; echo "${PRETTY_NAME:-unknown}")"
}

main() {
    need_root
    need_cmd unsquashfs mount umount cp grep

    if [[ -f "${MARKER}" && "${STRAWWU_FORCE:-0}" != "1" ]]; then
        log "already cloned ($(cat "${MARKER}")); set STRAWWU_FORCE=1 to redo"
        exit 0
    fi

    mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"
    local iso
    iso="$(download_iso)"
    extract_squashfs "${iso}"
    prepare_rootfs
    verify_rootfs

    date -Is > "${MARKER}"
    log "clone complete: ${ROOTFS_DIR}"
}

main "$@"

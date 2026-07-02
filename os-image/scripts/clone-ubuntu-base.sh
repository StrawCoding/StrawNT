#!/usr/bin/env bash
# clone-ubuntu-base.sh — Extract Ubuntu noble desktop live rootfs from official ISO.
#
# Noble (24.04+) live ISOs use layered casper/minimal*.squashfs; we merge layers
# then apt-install calamares-settings-ubuntu-common inside chroot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
OUTPUT_DIR="${REPO_ROOT}/os-image/output"
ISO_CACHE="${OUTPUT_DIR}/cache"

UBUNTU_VERSION="${STRAWWU_UBUNTU_VERSION:-24.04.2}"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
UBUNTU_SERIES="${UBUNTU_VERSION%.*}"
UBUNTU_MIRROR="${STRAWWU_UBUNTU_MIRROR:-https://old-releases.ubuntu.com/releases/${UBUNTU_VERSION}}"
ISO_URL="${UBUNTU_MIRROR}/${UBUNTU_ISO_NAME}"

ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
ISO_MOUNT="${WORK_DIR}/iso-mount"
MARKER="${WORK_DIR}/.clone-ubuntu-base-ok"
ISO_PATH_FILE="${WORK_DIR}/.source-iso-path"

log() { echo "==> $*" >&2; }
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

mount_iso() {
    local iso="$1"
    mkdir -p "${ISO_MOUNT}"
    if mountpoint -q "${ISO_MOUNT}" 2>/dev/null; then
        umount "${ISO_MOUNT}" || true
    fi
    mount -o loop,ro "${iso}" "${ISO_MOUNT}"
}

umount_iso() {
    if mountpoint -q "${ISO_MOUNT}" 2>/dev/null; then
        umount "${ISO_MOUNT}" || true
    fi
}

extract_monolithic() {
    local squashfs=""
    for candidate in \
        "${ISO_MOUNT}/casper/filesystem.squashfs" \
        "${ISO_MOUNT}/live/filesystem.squashfs"; do
        if [[ -f "${candidate}" ]]; then
            squashfs="${candidate}"
            break
        fi
    done
    [[ -n "${squashfs}" ]] || return 1

    log "monolithic ISO: unsquashfs ${squashfs}"
    rm -rf "${SQUASH_SRC}"
    unsquashfs -force -d "${SQUASH_SRC}" "${squashfs}"
    return 0
}

extract_layered() {
    local layers=()
    local base="${ISO_MOUNT}/casper/minimal.squashfs"
    local standard="${ISO_MOUNT}/casper/minimal.standard.squashfs"
    local lang="${ISO_MOUNT}/casper/minimal.en.squashfs"

    [[ -f "${base}" ]] || return 1
    layers+=("${base}")
    [[ -f "${standard}" ]] && layers+=("${standard}")
    if [[ -f "${lang}" ]]; then
        layers+=("${lang}")
    elif [[ -f "${ISO_MOUNT}/casper/minimal.no-languages.squashfs" ]]; then
        layers+=("${ISO_MOUNT}/casper/minimal.no-languages.squashfs")
    fi

    log "layered ISO: merging ${#layers[@]} squashfs layers"
    rm -rf "${SQUASH_SRC}"
    mkdir -p "${SQUASH_SRC}"
    local layer
    for layer in "${layers[@]}"; do
        log "unsquashfs layer $(basename "${layer}")"
        unsquashfs -force -d "${SQUASH_SRC}" "${layer}"
    done
    return 0
}

extract_rootfs_from_iso() {
    local iso="$1"
    mount_iso "${iso}"
    trap 'umount_iso' EXIT

    if extract_monolithic; then
        echo "monolithic" > "${WORK_DIR}/.iso-layout"
    elif extract_layered; then
        echo "layered" > "${WORK_DIR}/.iso-layout"
    else
        die "no supported squashfs layout in ISO (need filesystem.squashfs or minimal*.squashfs)"
    fi

    umount_iso
    trap - EXIT
}

unmount_chroot() {
    umount "${ROOTFS_DIR}/run" 2>/dev/null || umount -l "${ROOTFS_DIR}/run" 2>/dev/null || true
    umount "${ROOTFS_DIR}/dev/pts" 2>/dev/null || umount -l "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    umount "${ROOTFS_DIR}/sys" 2>/dev/null || umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
    umount "${ROOTFS_DIR}/proc" 2>/dev/null || umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
    umount "${ROOTFS_DIR}/dev" 2>/dev/null || umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
}

chroot_run() {
    mount --bind /dev  "${ROOTFS_DIR}/dev"
    mount --bind /proc "${ROOTFS_DIR}/proc"
    mount --bind /sys  "${ROOTFS_DIR}/sys"
    mount -t devpts devpts "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    mount --bind /run  "${ROOTFS_DIR}/run" 2>/dev/null || true
    trap 'unmount_chroot' EXIT
    chroot "${ROOTFS_DIR}" "$@"
    local rc=$?
    unmount_chroot
    trap - EXIT
    return "${rc}"
}

install_calamares() {
    if [[ -f "${ROOTFS_DIR}/usr/bin/calamares" ]]; then
        log "calamares already present in extracted rootfs"
        return 0
    fi

    log "installing calamares + calamares-settings-ubuntu-common in chroot"
    cp -f /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true
    chroot_run bash -c '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends \
            calamares \
            calamares-settings-ubuntu-common
    '
}

prepare_rootfs() {
    rm -rf "${ROOTFS_DIR}"
    cp -a "${SQUASH_SRC}" "${ROOTFS_DIR}"
    mkdir -p "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run"
    install_calamares
}

verify_rootfs() {
    log "verifying Ubuntu packages in rootfs"
    local required=(
        "/etc/os-release"
        "/usr/bin/calamares"
        "/etc/calamares/modules/mount.conf"
    )
    for f in "${required[@]}"; do
        [[ -e "${ROOTFS_DIR}${f}" ]] || die "missing in rootfs: ${f}"
    done
    [[ -d "${ROOTFS_DIR}/usr/share/doc/calamares-settings-ubuntu-common" ]] \
        || die "missing calamares-settings-ubuntu-common package"
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

    if [[ "${STRAWWU_SKIP_EXTRACT:-0}" == "1" && -f "${SQUASH_SRC}/etc/os-release" ]]; then
        log "STRAWWU_SKIP_EXTRACT=1: reusing extracted squashfs at ${SQUASH_SRC}"
        [[ -f "${ISO_PATH_FILE}" ]] || die "missing ${ISO_PATH_FILE} (need prior extract or full clone)"
    else
        local iso
        iso="$(download_iso)"
        echo "${iso}" > "${ISO_PATH_FILE}"
        extract_rootfs_from_iso "${iso}"
    fi

    prepare_rootfs
    verify_rootfs

    date -Is > "${MARKER}"
    log "clone complete: ${ROOTFS_DIR}"
}

main "$@"

#!/usr/bin/env bash
# sync-calamares-installer.sh — overlay upstream-aligned Calamares installer configs into rootfs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALLER_DIR="${REPO_ROOT}/os-image/config/calamares-installer"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing: ${ROOTFS_DIR}"
[[ -d "${INSTALLER_DIR}" ]] || die "calamares-installer overlay missing"

log "syncing Calamares installer overlay into rootfs"
cp -a "${INSTALLER_DIR}/." "${ROOTFS_DIR}/"
chmod 755 "${ROOTFS_DIR}/usr/local/lib/calamares/strawwu-post-install-marker.sh"
chmod 755 "${ROOTFS_DIR}/usr/local/sbin/strawwu-e2e-guest-runner.sh" 2>/dev/null || true

for required in \
    settings.conf \
    modules/partition.conf \
    modules/welcome.conf \
    modules/unpackfs.conf; do
    [[ -f "${ROOTFS_DIR}/etc/calamares/${required}" ]] \
        || die "overlay missing etc/calamares/${required}"
done

if ! grep -qE 'type:[[:space:]]*any' "${ROOTFS_DIR}/etc/calamares/modules/partition.conf"; then
    die "partition.conf must use devices.type: any"
fi

if grep -qE '(^|[[:space:]])- storage' "${ROOTFS_DIR}/etc/calamares/modules/welcome.conf" 2>/dev/null; then
    die "welcome.conf must not require storage check"
fi

if [[ "${STRAWWU_ENABLE_E2E:-0}" == "1" ]]; then
    if [[ -f "${ROOTFS_DIR}/etc/systemd/system/strawwu-e2e-guest-runner.service" ]]; then
        log "enabling install-e2e guest runner (STRAWWU_ENABLE_E2E=1)"
        mkdir -p "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
        ln -sf ../strawwu-e2e-guest-runner.service \
            "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/strawwu-e2e-guest-runner.service"
    fi
else
    log "production ISO: disabling install-e2e guest runner"
    rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/strawwu-e2e-guest-runner.service"
fi

install_e2e_guest_deps() {
    [[ "${STRAWWU_ENABLE_E2E:-0}" == "1" ]] || return 0
    local need_install=0
    [[ -f "${ROOTFS_DIR}/usr/bin/xdotool" ]] || need_install=1
    [[ -f "${ROOTFS_DIR}/usr/bin/Xvfb" ]] || need_install=1
    [[ "${need_install}" -eq 0 ]] && return 0
    log "installing E2E deps in rootfs (xdotool + xvfb)"
    mount --bind /dev "${ROOTFS_DIR}/dev"
    mount --bind /proc "${ROOTFS_DIR}/proc"
    mount --bind /sys "${ROOTFS_DIR}/sys"
    cp -f /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true
    chroot "${ROOTFS_DIR}" bash -c '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends xdotool xvfb
    ' || die "E2E deps install failed"
    umount "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" 2>/dev/null || true
}

install_e2e_guest_deps

log "calamares installer overlay OK"

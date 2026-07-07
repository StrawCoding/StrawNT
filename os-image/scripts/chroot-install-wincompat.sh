#!/usr/bin/env bash
# chroot-install-wincompat.sh — Install strawwu-wincompat (strawwu CLI) in rootfs.
#
# Wave W0: Live ISO rootfs baseline for `strawwu status`.
# Idempotent; syncs rootfs → squashfs-root for preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/base-marker.sh
source "${SCRIPT_DIR}/lib/base-marker.sh"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.wincompat-ok"
PURGE_MARKER="${WORK_DIR}/.purge-ubuntu-telemetry-ok"
DEB_BUILD="${REPO_ROOT}/os-image/debs/strawwu-wincompat/build-deb.sh"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot wincompat setup)"
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

verify_prerequisites() {
    die_unless_base_marker "${WORK_DIR}"
    [[ -f "${PURGE_MARKER}" ]] || die "run chroot-purge-ubuntu-telemetry first (${PURGE_MARKER} missing)"
    [[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing: ${ROOTFS_DIR}"
    [[ -x "${DEB_BUILD}" ]] || die "missing build script: ${DEB_BUILD}"
    unmount_chroot
}

build_deb() {
    log "building strawwu-wincompat deb"
    STRAWWU_VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}" \
        bash "${DEB_BUILD}"
}

install_in_chroot() {
    local deb_file
    deb_file="$(ls -1 "${REPO_ROOT}/os-image/debs/strawwu-wincompat/output/"strawwu-wincompat_*.deb 2>/dev/null | tail -1)"
    [[ -n "${deb_file}" && -f "${deb_file}" ]] || die "strawwu-wincompat .deb not found"

    log "installing strawwu-wincompat inside chroot"
    cp -f "${deb_file}" "${ROOTFS_DIR}/tmp/strawwu-wincompat.deb"

    local inner="${WORK_DIR}/chroot-wincompat-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

dpkg -i /tmp/strawwu-wincompat.deb
rm -f /tmp/strawwu-wincompat.deb

command -v strawwu >/dev/null
test -x /usr/bin/strawwu
test -f /usr/share/strawwu/wincompat/baseline.yaml
strawwu status | grep -q 'status'
strawwu version | grep -q 'strawwu'
dpkg-query -W -f='${Status}' strawwu-wincompat 2>/dev/null | grep -q "ok installed"
INNER
    chmod 755 "${inner}"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-wincompat-inner.sh"
    chroot_run /tmp/chroot-wincompat-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-wincompat-inner.sh"
}

sync_squashfs() {
    if [[ ! -d "${SQUASH_SRC}" ]]; then
        log "squashfs-root missing — skipping sync"
        return 0
    fi
    log "syncing rootfs → squashfs-root (wincompat files)"
    rsync -a \
        "${ROOTFS_DIR}/usr/bin/strawwu" \
        "${SQUASH_SRC}/usr/bin/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/wincompat/" \
        "${SQUASH_SRC}/usr/share/strawwu/wincompat/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/var/lib/dpkg/status" \
        "${ROOTFS_DIR}/var/lib/dpkg/status-old" \
        "${ROOTFS_DIR}/var/lib/dpkg/info/" \
        "${SQUASH_SRC}/var/lib/dpkg/" 2>/dev/null || true
}

write_marker() {
    date -Iseconds > "${MARKER}"
    log "marker written: ${MARKER}"
}

main() {
    need_root
    verify_prerequisites
    build_deb
    install_in_chroot
    sync_squashfs
    write_marker
    log "strawwu-wincompat chroot install complete"
}

main "$@"

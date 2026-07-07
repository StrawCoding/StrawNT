#!/usr/bin/env bash
# chroot-install-calamares-settings.sh — Install strawwu-calamares-settings in rootfs.
#
# Replaces calamares-settings-ubuntu-common with StrawWU-owned settings deb.
# Idempotent; syncs calamares tree → squashfs-root for preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/base-marker.sh
source "${SCRIPT_DIR}/lib/base-marker.sh"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.calamares-settings-ok"
DEB_BUILD="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/build-deb.sh"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot calamares-settings setup)"
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
    [[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing: ${ROOTFS_DIR}"
    [[ -x "${DEB_BUILD}" ]] || die "missing build script: ${DEB_BUILD}"
    unmount_chroot
}

build_deb() {
    log "building strawwu-calamares-settings deb"
    STRAWWU_VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}" \
        bash "${DEB_BUILD}"
}

install_in_chroot() {
    local deb_file
    deb_file="$(ls -1 "${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/output/"strawwu-calamares-settings_*.deb 2>/dev/null | tail -1)"
    [[ -n "${deb_file}" && -f "${deb_file}" ]] || die "strawwu-calamares-settings .deb not found"

    log "installing strawwu-calamares-settings inside chroot"
    cp -f "${deb_file}" "${ROOTFS_DIR}/tmp/strawwu-calamares-settings.deb"

    local inner="${WORK_DIR}/chroot-calamares-settings-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! command -v calamares >/dev/null 2>&1; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y --no-install-recommends calamares
fi

# Remove upstream ubuntu-common if present (W2-I1 replacement).
if dpkg-query -W -f='${Status}' calamares-settings-ubuntu-common 2>/dev/null | grep -q "ok installed"; then
    apt-get remove -y --purge calamares-settings-ubuntu-common || dpkg -r calamares-settings-ubuntu-common
fi

dpkg -i /tmp/strawwu-calamares-settings.deb
rm -f /tmp/strawwu-calamares-settings.deb

dpkg-query -W -f='${Status}' strawwu-calamares-settings | grep -q "ok installed"
test -f /etc/calamares/settings.conf
test -f /etc/calamares/modules/partition.conf
grep -qE 'type:[[:space:]]*any' /etc/calamares/modules/partition.conf
grep -q 'branding: strawwu' /etc/calamares/settings.conf
! test -f /usr/bin/snap-seed-glue
! dpkg-query -W calamares-settings-ubuntu-common 2>/dev/null | grep -q "ok installed"
INNER
    chmod 755 "${inner}"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-calamares-settings-inner.sh"
    chroot_run /tmp/chroot-calamares-settings-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-calamares-settings-inner.sh"
}

sync_squashfs() {
    if [[ ! -d "${SQUASH_SRC}" ]]; then
        log "squashfs-root missing — skipping sync"
        return 0
    fi
    log "syncing calamares settings rootfs → squashfs-root"
    rsync -a \
        "${ROOTFS_DIR}/etc/calamares/" \
        "${SQUASH_SRC}/etc/calamares/"
    rsync -a \
        "${ROOTFS_DIR}/usr/local/lib/calamares/" \
        "${SQUASH_SRC}/usr/local/lib/calamares/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/libexec/fixconkeys-part1" \
        "${ROOTFS_DIR}/usr/libexec/fixconkeys-part2" \
        "${SQUASH_SRC}/usr/libexec/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/x86_64-linux-gnu/calamares/modules/" \
        "${SQUASH_SRC}/usr/lib/x86_64-linux-gnu/calamares/modules/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/doc/strawwu-calamares-settings/" \
        "${SQUASH_SRC}/usr/share/doc/strawwu-calamares-settings/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/var/lib/dpkg/status" \
        "${ROOTFS_DIR}/var/lib/dpkg/status-old" \
        "${ROOTFS_DIR}/var/lib/dpkg/info/" \
        "${SQUASH_SRC}/var/lib/dpkg/" 2>/dev/null || true
    # Purge ubuntu-common leftovers from squashfs mirror (snap-seed-glue etc.).
    rm -f "${SQUASH_SRC}/usr/bin/snap-seed-glue"
    rm -rf "${SQUASH_SRC}/usr/share/doc/calamares-settings-ubuntu-common"
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
    log "strawwu-calamares-settings chroot install complete"
}

main "$@"

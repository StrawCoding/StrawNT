#!/usr/bin/env bash
# chroot-install-firstboot.sh — Install strawwu-firstboot in rootfs (or verify via target-setup).
#
# Idempotent; syncs rootfs → squashfs-root for preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.firstboot-ok"
TARGET_MARKER="${WORK_DIR}/.target-setup-ok"
DEB_BUILD="${REPO_ROOT}/os-image/debs/strawwu-firstboot/build-deb.sh"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot firstboot setup)"
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
    [[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing: ${ROOTFS_DIR}"
    [[ -x "${DEB_BUILD}" ]] || die "missing build script: ${DEB_BUILD}"
    unmount_chroot
}

build_deb() {
    log "building strawwu-firstboot deb"
    STRAWWU_VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}" \
        bash "${DEB_BUILD}"
}

already_installed() {
    dpkg-query --root="${ROOTFS_DIR}" -W -f='${Status}' strawwu-firstboot 2>/dev/null | grep -q "ok installed"
}

install_in_chroot() {
    if already_installed; then
        log "strawwu-firstboot already installed in rootfs"
        return 0
    fi

    if [[ -f "${TARGET_MARKER}" ]]; then
        log "target-setup marker present but firstboot missing — installing deb directly"
    fi

    local deb_file
    deb_file="$(ls -1 "${REPO_ROOT}/os-image/debs/strawwu-firstboot/output/"strawwu-firstboot_*.deb 2>/dev/null | tail -1)"
    [[ -n "${deb_file}" && -f "${deb_file}" ]] || die "strawwu-firstboot .deb not found"

    log "installing strawwu-firstboot inside chroot"
    cp -f "${deb_file}" "${ROOTFS_DIR}/tmp/strawwu-firstboot.deb"

    local inner="${WORK_DIR}/chroot-firstboot-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

need_pkgs=(python3 python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 libadwaita-1-0)
missing=()
for pkg in "${need_pkgs[@]}"; do
    dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "ok installed" || missing+=("${pkg}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y --no-install-recommends "${missing[@]}" 2>/dev/null || true
fi

dpkg -i /tmp/strawwu-firstboot.deb || apt-get install -f -y
rm -f /tmp/strawwu-firstboot.deb

command -v strawwu-firstboot >/dev/null
test -f /etc/xdg/autostart/strawwu-firstboot.desktop
test -f /usr/share/strawwu/firstboot/firstboot-manifest.yaml
dpkg-query -W -f='${Status}' strawwu-firstboot 2>/dev/null | grep -q "ok installed"
INNER
    chmod 755 "${inner}"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-firstboot-inner.sh"
    chroot_run /tmp/chroot-firstboot-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-firstboot-inner.sh"
}

sync_squashfs() {
    if [[ ! -d "${SQUASH_SRC}" ]]; then
        log "squashfs-root missing — skipping sync"
        return 0
    fi
    log "syncing rootfs → squashfs-root (firstboot files)"
    install -d "${SQUASH_SRC}/etc/xdg/autostart" "${SQUASH_SRC}/usr/share/strawwu/locale"
    rsync -a \
        "${ROOTFS_DIR}/usr/bin/strawwu-firstboot" \
        "${SQUASH_SRC}/usr/bin/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-firstboot/" \
        "${SQUASH_SRC}/usr/lib/strawwu-firstboot/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/firstboot/" \
        "${SQUASH_SRC}/usr/share/strawwu/firstboot/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/locale/firstboot."*.yaml \
        "${SQUASH_SRC}/usr/share/strawwu/locale/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/applications/strawwu-firstboot.desktop" \
        "${SQUASH_SRC}/usr/share/applications/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/etc/xdg/autostart/strawwu-firstboot.desktop" \
        "${SQUASH_SRC}/etc/xdg/autostart/" 2>/dev/null || true
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
    log "strawwu-firstboot chroot install complete"
}

main "$@"

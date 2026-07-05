#!/usr/bin/env bash
# chroot-install-update-notifier.sh — Install strawwu-update-notifier in rootfs.
#
# Replaces update-notifier with strawwu-update-notifier (Provides update-notifier).
# Idempotent; syncs rootfs → squashfs-root for preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.update-notifier-ok"
CLONE_MARKER="${WORK_DIR}/.clone-ubuntu-base-ok"
PURGE_MARKER="${WORK_DIR}/.purge-ubuntu-telemetry-ok"
DEB_BUILD="${REPO_ROOT}/os-image/debs/strawwu-update-notifier/build-deb.sh"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot update-notifier setup)"
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
    [[ -f "${CLONE_MARKER}" ]] || die "run clone-ubuntu-base first (${CLONE_MARKER} missing)"
    [[ -f "${PURGE_MARKER}" ]] || die "run chroot-purge-ubuntu-telemetry first (${PURGE_MARKER} missing)"
    [[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing: ${ROOTFS_DIR}"
    [[ -x "${DEB_BUILD}" ]] || die "missing build script: ${DEB_BUILD}"
    unmount_chroot
}

build_deb() {
    log "building strawwu-update-notifier deb"
    STRAWWU_VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}" \
        bash "${DEB_BUILD}"
}

install_in_chroot() {
    local deb_file
    deb_file="$(ls -1 "${REPO_ROOT}/os-image/debs/strawwu-update-notifier/output/"strawwu-update-notifier_*.deb 2>/dev/null | tail -1)"
    [[ -n "${deb_file}" && -f "${deb_file}" ]] || die "strawwu-update-notifier .deb not found"

    log "installing strawwu-update-notifier inside chroot (replaces update-notifier)"
    cp -f "${deb_file}" "${ROOTFS_DIR}/tmp/strawwu-update-notifier.deb"

    local inner="${WORK_DIR}/chroot-update-notifier-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Remove upstream update-notifier so our package can replace it.
if dpkg-query -W -f='${Status}' update-notifier 2>/dev/null | grep -q "ok installed"; then
    apt-get remove -y --purge update-notifier 2>/dev/null || true
    dpkg --purge update-notifier 2>/dev/null || true
fi

need_pkgs=(python3 libnotify-bin apt)
missing=()
for pkg in "${need_pkgs[@]}"; do
    dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "ok installed" || missing+=("${pkg}")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y --no-install-recommends "${missing[@]}" 2>/dev/null || true
fi

dpkg -i /tmp/strawwu-update-notifier.deb
rm -f /tmp/strawwu-update-notifier.deb

command -v strawwu-update-notifier >/dev/null
test -f /etc/apt/apt.conf.d/99strawwu-update-notifier
test -f /usr/share/strawwu/update-notifier/backup-copy.yaml
! dpkg-query -W -f='${Status}' update-notifier 2>/dev/null | grep -q "ok installed"
dpkg-query -W -f='${Status}' strawwu-update-notifier 2>/dev/null | grep -q "ok installed"
INNER
    chmod 755 "${inner}"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-update-notifier-inner.sh"
    chroot_run /tmp/chroot-update-notifier-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-update-notifier-inner.sh"
}

sync_squashfs() {
    if [[ ! -d "${SQUASH_SRC}" ]]; then
        log "squashfs-root missing — skipping sync"
        return 0
    fi
    log "syncing rootfs → squashfs-root (update-notifier files)"
    rsync -a \
        "${ROOTFS_DIR}/usr/bin/strawwu-update-notifier" \
        "${SQUASH_SRC}/usr/bin/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-update-notifier/" \
        "${SQUASH_SRC}/usr/lib/strawwu-update-notifier/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/update-notifier/" \
        "${SQUASH_SRC}/usr/share/strawwu/update-notifier/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/applications/strawwu-update-notifier.desktop" \
        "${SQUASH_SRC}/usr/share/applications/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/etc/apt/apt.conf.d/99strawwu-update-notifier" \
        "${SQUASH_SRC}/etc/apt/apt.conf.d/" 2>/dev/null || true
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
    log "strawwu-update-notifier chroot install complete"
}

main "$@"

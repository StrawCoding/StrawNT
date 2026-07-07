#!/usr/bin/env bash
# chroot-install-bug-reporter.sh — Install strawwu-bug-reporter in rootfs.
#
# Idempotent chroot hook: dpkg -i strawwu-bug-reporter, postinst creates
# /var/log/strawwu. Syncs rootfs → squashfs-root for preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/base-marker.sh
source "${SCRIPT_DIR}/lib/base-marker.sh"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.bug-reporter-ok"
PURGE_MARKER="${WORK_DIR}/.purge-ubuntu-telemetry-ok"
DEB_BUILD="${REPO_ROOT}/os-image/debs/strawwu-bug-reporter/build-deb.sh"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot bug-reporter setup)"
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
    log "building strawwu-bug-reporter deb"
    STRAWWU_VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}" \
        bash "${DEB_BUILD}"
}

install_in_chroot() {
    local deb_file
    deb_file="$(ls -1 "${REPO_ROOT}/os-image/debs/strawwu-bug-reporter/output/"strawwu-bug-reporter_*.deb 2>/dev/null | tail -1)"
    [[ -n "${deb_file}" && -f "${deb_file}" ]] || die "strawwu-bug-reporter .deb not found"

    log "installing strawwu-bug-reporter inside chroot"
    cp -f "${deb_file}" "${ROOTFS_DIR}/tmp/strawwu-bug-reporter.deb"

    local inner="${WORK_DIR}/chroot-bug-reporter-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Pull GTK/GI deps if missing (download-only to avoid meta breakage after W1-B1 purge).
need_pkgs=(python3 python3-gi gir1.2-gtk-3.0)
missing=()
for pkg in "${need_pkgs[@]}"; do
    dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "ok installed" || missing+=("${pkg}")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    apt-get update -qq 2>/dev/null || true
    if ! apt-get install -y --no-install-recommends "${missing[@]}" 2>/dev/null; then
        mkdir -p /tmp/bug-reporter-debs
        cd /tmp/bug-reporter-debs
        apt-get download "${missing[@]}" 2>/dev/null || true
        dpkg -i --force-depends ./*.deb 2>/dev/null || true
        apt-get -f install -y --no-install-recommends 2>/dev/null || true
    fi
fi

dpkg -i /tmp/strawwu-bug-reporter.deb
rm -f /tmp/strawwu-bug-reporter.deb

command -v strawwu-bug-report >/dev/null
test -d /var/log/strawwu
test -f /var/lib/strawwu/bug-upload-consent
grep -q 'upload_opt_in=false' /var/lib/strawwu/bug-upload-consent
INNER
    chmod 755 "${inner}"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-bug-reporter-inner.sh"
    chroot_run /tmp/chroot-bug-reporter-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-bug-reporter-inner.sh"
}

sync_squashfs() {
    if [[ ! -d "${SQUASH_SRC}" ]]; then
        log "squashfs-root missing — skipping sync"
        return 0
    fi
    log "syncing rootfs → squashfs-root (bug-reporter files)"
    rsync -a --delete \
        "${ROOTFS_DIR}/usr/bin/strawwu-bug-report" \
        "${ROOTFS_DIR}/usr/bin/strawwu-bug-report-gtk" \
        "${SQUASH_SRC}/usr/bin/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-bug-reporter/" \
        "${SQUASH_SRC}/usr/lib/strawwu-bug-reporter/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/applications/strawwu-bug-report-gtk.desktop" \
        "${SQUASH_SRC}/usr/share/applications/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/doc/strawwu-bug-reporter/" \
        "${SQUASH_SRC}/usr/share/doc/strawwu-bug-reporter/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/var/lib/dpkg/status" \
        "${ROOTFS_DIR}/var/lib/dpkg/status-old" \
        "${ROOTFS_DIR}/var/lib/dpkg/info/" \
        "${SQUASH_SRC}/var/lib/dpkg/" 2>/dev/null || true
    mkdir -p "${SQUASH_SRC}/var/log/strawwu" "${SQUASH_SRC}/var/lib/strawwu"
    rsync -a "${ROOTFS_DIR}/var/log/strawwu/" "${SQUASH_SRC}/var/log/strawwu/" 2>/dev/null || true
    rsync -a "${ROOTFS_DIR}/var/lib/strawwu/bug-upload-consent" "${SQUASH_SRC}/var/lib/strawwu/" 2>/dev/null || true
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
    log "strawwu-bug-reporter chroot install complete"
}

main "$@"

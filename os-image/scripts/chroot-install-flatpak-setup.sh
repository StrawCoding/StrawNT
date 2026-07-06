#!/usr/bin/env bash
# chroot-install-flatpak-setup.sh — Install flatpak + strawwu-flatpak-setup in rootfs.
#
# Idempotent chroot hook: apt install flatpak, dpkg -i strawwu-flatpak-setup,
# postinst registers Flathub system remote. Syncs rootfs → squashfs-root for preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.flatpak-setup-ok"
CLONE_MARKER="${WORK_DIR}/.clone-ubuntu-base-ok"
PURGE_MARKER="${WORK_DIR}/.purge-ubuntu-telemetry-ok"
DEB_BUILD="${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/build-deb.sh"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot flatpak setup)"
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

build_setup_deb() {
    log "building strawwu-flatpak-setup deb"
    STRAWWU_VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}" \
        bash "${DEB_BUILD}"
}

install_in_chroot() {
    local deb_file
    deb_file="$(ls -1 "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/output/"strawwu-flatpak-setup_*.deb 2>/dev/null | tail -1)"
    [[ -n "${deb_file}" && -f "${deb_file}" ]] || die "strawwu-flatpak-setup .deb not found — run build-deb first"

    log "installing flatpak + strawwu-flatpak-setup inside chroot"
    cp -f /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true
    cp -f "${deb_file}" "${ROOTFS_DIR}/tmp/strawwu-flatpak-setup.deb"

    local inner="${WORK_DIR}/chroot-flatpak-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# W1-B1 removed snapd; purge snap transition packages that block apt.
apt-mark unhold firefox thunderbird 2>/dev/null || true
dpkg --purge --force-depends firefox thunderbird 2>/dev/null || true
dpkg -l 'thunderbird-locale-*' 2>/dev/null | awk '/^ii/ {print $2}' \
    | xargs -r dpkg --purge --force-depends 2>/dev/null || true

apt-get update -qq

# Post-purge rootfs has broken meta Depends; download flatpak stack and force-install.
mkdir -p /tmp/flatpak-debs
cd /tmp/flatpak-debs
rm -f *.deb 2>/dev/null || true

flatpak_pkgs=(
    flatpak libostree-1-1 bubblewrap xdg-dbus-proxy libappstream5
    libarchive13t64 libmalcontent-0-0 libjson-glib-1.0-0 fuse3 libcomposefs1
)
# noble: libfuse3-3; resolute: libfuse3-4
if apt-cache show libfuse3-3 &>/dev/null; then
    flatpak_pkgs+=(libfuse3-3)
elif apt-cache show libfuse3-4 &>/dev/null; then
    flatpak_pkgs+=(libfuse3-4)
else
    echo "no libfuse3 package found in apt cache" >&2
    exit 1
fi
for pkg in "${flatpak_pkgs[@]}"; do
    apt-get download "${pkg}"
done

dpkg -i --force-depends *.deb

dpkg -i /tmp/strawwu-flatpak-setup.deb || apt-get install -f -y --no-install-recommends

rm -rf /tmp/flatpak-debs
rm -f /tmp/strawwu-flatpak-setup.deb

if ! command -v flatpak >/dev/null 2>&1; then
    echo "flatpak CLI missing after install" >&2
    exit 1
fi

flatpak --version

if ! flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
    echo "flathub system remote missing after postinst" >&2
    exit 1
fi

echo "flathub system remote OK"
INNER
    chmod +x "${inner}"
    mkdir -p "${ROOTFS_DIR}/tmp"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-flatpak-inner.sh"
    chroot_run bash /tmp/chroot-flatpak-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-flatpak-inner.sh"
}

sync_squashfs_baseline() {
    [[ "${STRAWWU_SKIP_SQUASHFS_SYNC:-0}" == "1" ]] && {
        log "STRAWWU_SKIP_SQUASHFS_SYNC=1: skip squashfs-root sync"
        return 0
    }
    log "syncing flatpak rootfs → squashfs-root for preflight baseline"
    rsync -a --delete \
        --exclude='dev/' \
        --exclude='proc/' \
        --exclude='sys/' \
        --exclude='run/' \
        "${ROOTFS_DIR}/" "${SQUASH_SRC}/"
}

verify_install() {
    [[ -x "${ROOTFS_DIR}/usr/bin/flatpak" ]] || die "flatpak CLI missing in rootfs"
    package_installed_in_rootfs() {
        awk -v p="$1" '
            /^Package: / { cur=$2 }
            /^Status: / && / ok installed/ && cur==p { found=1 }
            END { exit !found }
        ' "${ROOTFS_DIR}/var/lib/dpkg/status"
    }
    package_installed_in_rootfs flatpak || die "flatpak package not installed"
    package_installed_in_rootfs strawwu-flatpak-setup || die "strawwu-flatpak-setup not installed"

    if [[ -f "${ROOTFS_DIR}/etc/flatpak/remotes.d/flathub.flatpakrepo" ]]; then
        log "flathub remote file present in etc/flatpak/remotes.d"
    elif [[ -f "${ROOTFS_DIR}/var/lib/flatpak/repo/config" ]] \
        && grep -q '^\[remote "flathub"\]' "${ROOTFS_DIR}/var/lib/flatpak/repo/config"; then
        log "flathub remote present in flatpak repo config"
    else
        die "flathub system remote not found in rootfs"
    fi
    log "post-install verification OK"
}

main() {
    need_root
    verify_prerequisites

    if [[ -f "${MARKER}" && "${STRAWWU_FORCE:-0}" != "1" ]]; then
        log "flatpak setup already done ($(cat "${MARKER}")); set STRAWWU_FORCE=1 to redo"
        exit 0
    fi

    build_setup_deb
    install_in_chroot
    verify_install
    sync_squashfs_baseline

    date -Is > "${MARKER}"
    log "flatpak setup complete: ${ROOTFS_DIR}"
}

main "$@"

#!/usr/bin/env bash
# chroot-purge-ubuntu-telemetry.sh — Idempotent purge of Ubuntu telemetry, Pro, Snap.
#
# Operates on os-image/work/rootfs via chroot. Syncs back to squashfs-root for
# preflight baseline scans. Does NOT remove ubuntu-keyring or casper/desktop meta.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/base-marker.sh
source "${SCRIPT_DIR}/lib/base-marker.sh"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.purge-ubuntu-telemetry-ok"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot purge)"
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
    unmount_chroot
    [[ -f "${ROOTFS_DIR}/usr/share/keyrings/ubuntu-archive-keyring.gpg" ]] \
        || [[ -f "${ROOTFS_DIR}/etc/apt/trusted.gpg.d/ubuntu-keyring.gpg" ]] \
        || die "ubuntu-keyring must remain — aborting"
    [[ -f "${ROOTFS_DIR}/usr/bin/calamares" ]] || die "calamares must remain — aborting"
}

purge_in_chroot() {
    log "purging telemetry / pro / snap inside chroot"
    cp -f /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true

    local purge_script="${WORK_DIR}/chroot-purge-inner.sh"
    cat > "${purge_script}" <<'INNER'
#!/usr/bin/env bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

systemctl disable apport.service apport-autoreport.service whoopsie.path 2>/dev/null || true
systemctl stop apport.service whoopsie.path snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true

apt-mark unhold \
    snapd snap-confine firefox thunderbird \
    apport apport-gtk ubuntu-pro-client ubuntu-pro-client-l10n \
    ubuntu-advantage-desktop-daemon ubuntu-report whoopsie \
    2>/dev/null || true

apt-mark manual ubuntu-desktop ubuntu-desktop-minimal ubuntu-minimal xorg xserver-xorg 2>/dev/null || true

apt-get purge -y \
    apport apport-core-dump-handler apport-gtk apport-symptoms python3-apport \
    2>/dev/null || true
apt-get purge -y whoopsie whoopsie-preferences python3-apport 2>/dev/null || true
apt-get purge -y ubuntu-report 2>/dev/null || true

for pkg in ubuntu-advantage-desktop-daemon ubuntu-pro-client-l10n ubuntu-pro-client; do
    dpkg --remove --force-depends "${pkg}" 2>/dev/null || true
    dpkg --purge --force-depends "${pkg}" 2>/dev/null || true
done

for snap_dir in /snap /var/lib/snapd /root/snap; do
    [[ -d "${snap_dir}" ]] && rm -rf "${snap_dir}"
done
find /home -maxdepth 2 -type d -name snap -exec rm -rf {} + 2>/dev/null || true

apt-get purge -y firefox thunderbird 2>/dev/null || true
apt-get purge -y 'thunderbird-locale-*' 2>/dev/null || true
dpkg --purge --force-all snapd snap-confine 2>/dev/null || true
apt-get purge -y snapd snap-confine 2>/dev/null || true
dpkg-query -W -f='${Package}\n' 'ubuntu-core*' 2>/dev/null \
    | xargs -r apt-get purge -y 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean -y 2>/dev/null || true

apt-get install -y --no-install-recommends \
    ubuntu-minimal ubuntu-desktop xorg gnome-control-center \
    2>/dev/null || true

apt-mark unhold \
    snapd snap-confine firefox thunderbird \
    apport apport-gtk ubuntu-pro-client ubuntu-pro-client-l10n \
    ubuntu-advantage-desktop-daemon ubuntu-report whoopsie \
    2>/dev/null || true
apt-get purge -y \
    apport apport-core-dump-handler apport-gtk apport-symptoms python3-apport \
    whoopsie whoopsie-preferences ubuntu-report \
    snapd snap-confine firefox thunderbird \
    2>/dev/null || true
apt-get purge -y 'thunderbird-locale-*' 2>/dev/null || true
for pkg in ubuntu-advantage-desktop-daemon ubuntu-pro-client-l10n ubuntu-pro-client; do
    dpkg --remove --force-depends "${pkg}" 2>/dev/null || true
    dpkg --purge --force-depends "${pkg}" 2>/dev/null || true
done

mkdir -p /etc/default
printf "%s\n" "enabled=0" > /etc/default/apport
rm -f /etc/apport/crashdb.conf /etc/apport/blacklist.d/* 2>/dev/null || true

apt-mark hold \
    snapd snap-confine firefox thunderbird \
    apport apport-gtk ubuntu-pro-client ubuntu-pro-client-l10n \
    ubuntu-advantage-desktop-daemon ubuntu-report whoopsie \
    2>/dev/null || true

if ! dpkg -s ubuntu-minimal 2>/dev/null | grep -q '^Status: install ok installed'; then
    apt-get install -y -o DPkg::Options::="--force-depends" ubuntu-minimal 2>/dev/null || true
fi
if ! dpkg -s ubuntu-desktop 2>/dev/null | grep -q '^Status: install ok installed'; then
    (cd /tmp && apt-get download ubuntu-desktop ubuntu-desktop-minimal 2>/dev/null \
        && dpkg -i --force-depends ./ubuntu-desktop*.deb) 2>/dev/null || true
fi
apt-get install -y -o DPkg::Options::="--force-depends" --no-install-recommends \
    xserver-xorg xorg gnome-control-center \
    gnome-shell gdm3 session-migration mutter ubuntu-session \
    gnome-shell-ubuntu-extensions \
    2>/dev/null || true
# Fallback: force-install desktop stack when apt meta is broken after telemetry purge.
cd /tmp
for pkg in gnome-control-center gnome-shell gdm3 session-migration mutter ubuntu-session; do
    apt-get download "${pkg}" 2>/dev/null || true
done
dpkg -i --force-depends ./*.deb 2>/dev/null || true
rm -f ./*.deb 2>/dev/null || true

mkdir -p /snap
chmod 755 /snap
INNER
    chmod +x "${purge_script}"
    mkdir -p "${ROOTFS_DIR}/tmp"
    cp -f "${purge_script}" "${ROOTFS_DIR}/tmp/chroot-purge-inner.sh"
    chroot_run bash /tmp/chroot-purge-inner.sh
    rm -f "${purge_script}" "${ROOTFS_DIR}/tmp/chroot-purge-inner.sh"
}

sync_squashfs_baseline() {
    [[ "${STRAWWU_SKIP_SQUASHFS_SYNC:-0}" == "1" ]] && {
        log "STRAWWU_SKIP_SQUASHFS_SYNC=1: skip squashfs-root sync"
        return 0
    }
    log "syncing purged rootfs → squashfs-root for preflight baseline"
    rsync -a --delete \
        --exclude='dev/' \
        --exclude='proc/' \
        --exclude='sys/' \
        --exclude='run/' \
        "${ROOTFS_DIR}/" "${SQUASH_SRC}/"
}

verify_purge() {
    local status="${ROOTFS_DIR}/var/lib/dpkg/status"
    local forbidden=(
        apport apport-core-dump-handler whoopsie ubuntu-report
        ubuntu-pro-client ubuntu-pro-client-l10n
        ubuntu-advantage-desktop-daemon snapd snap-confine
    )
    local pkg
    for pkg in "${forbidden[@]}"; do
        if awk -v p="${pkg}" '
            /^Package: / { cur=$2 }
            /^Status: / && / ok installed/ && cur==p { found=1 }
            END { exit !found }
        ' "${status}"; then
            die "still installed after purge: ${pkg}"
        fi
    done

    for required in /etc/os-release /usr/bin/calamares /usr/share/keyrings/ubuntu-archive-keyring.gpg; do
        [[ -e "${ROOTFS_DIR}${required}" ]] || die "required path missing after purge: ${required}"
    done

    local desktop_meta=(ubuntu-minimal ubuntu-desktop)
    for pkg in "${desktop_meta[@]}"; do
        if awk -v p="${pkg}" '
            /^Package: / { cur=$2 }
            /^Status: / && / ok installed/ && cur==p { found=1 }
            END { exit !found }
        ' "${status}"; then
            log "retained ${pkg}"
        else
            die "desktop meta missing after purge: ${pkg}"
        fi
    done
    log "post-purge verification OK"
}

main() {
    need_root
    verify_prerequisites

    if [[ -f "${MARKER}" && "${STRAWWU_FORCE:-0}" != "1" ]]; then
        log "already purged ($(cat "${MARKER}")); set STRAWWU_FORCE=1 to redo"
        exit 0
    fi

    purge_in_chroot
    verify_purge
    sync_squashfs_baseline

    date -Is > "${MARKER}"
    log "purge complete: ${ROOTFS_DIR}"
}

main "$@"

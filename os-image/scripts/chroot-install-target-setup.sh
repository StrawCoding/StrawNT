#!/usr/bin/env bash
# chroot-install-target-setup.sh — Install strawwu-target-setup + staged target debs in rootfs.
#
# Stages StrawWU debs for Calamares chroot hook and installs desktop stack into rootfs.
# Idempotent; syncs rootfs → squashfs-root for preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/base-marker.sh
source "${SCRIPT_DIR}/lib/base-marker.sh"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.target-setup-ok"
DEBS_MARKER="${WORK_DIR}/.debs-rebuild-ok"
PURGE_MARKER="${WORK_DIR}/.purge-ubuntu-telemetry-ok"
DEBS_ROOT="${REPO_ROOT}/os-image/debs"
STAGED="${ROOTFS_DIR}/usr/share/strawwu/target-setup/staged-debs"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot target-setup)"
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
    unmount_chroot
}

build_debs() {
    bash "${SCRIPT_DIR}/build-os-debs.sh"
}

latest_deb() {
    local pkg="$1"
    local version="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
    local arch=all
    case "${pkg}" in
        strawwu-desktop|strawwu-minimal|strawwu-wincompat) arch=amd64 ;;
    esac
    local exact="${DEBS_ROOT}/${pkg}/output/${pkg}_${version}_${arch}.deb"
    if [[ -f "${exact}" ]]; then
        echo "${exact}"
        return 0
    fi
    ls -1t "${DEBS_ROOT}/${pkg}/output/${pkg}"_*.deb 2>/dev/null | head -1
}

stage_debs() {
    local version="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
    install -d -m 0755 "${STAGED}"
    rm -f "${STAGED}"/*.deb

    local pkg deb
    for pkg in strawwu-initd strawwu-wincompat strawwu-device-proxy strawwu-shell strawwu-session strawwu-greeter strawwu-update-notifier strawwu-software-sources strawwu-bug-reporter strawwu-drivers strawwu-laptop \
        strawwu-flatpak-setup strawwu-l10n-ime strawwu-firstboot strawwu-install-init strawwu-desktop-actions strawwu-registry-hooks strawwu-initramfs-hooks strawwu-target-identity strawwu-disable-upstream-init strawwu-minimal strawwu-desktop; do
        deb="$(latest_deb "${pkg}")"
        [[ -n "${deb}" && -f "${deb}" ]] || die "deb missing for ${pkg}"
        cp -f "${deb}" "${STAGED}/"
        log "staged ${deb##*/}"
    done

    deb="$(latest_deb strawwu-target-setup)"
    [[ -n "${deb}" && -f "${deb}" ]] || die "strawwu-target-setup .deb not found"
    cp -f "${deb}" "${ROOTFS_DIR}/tmp/strawwu-target-setup.deb"

    deb="$(latest_deb strawwu-live-install-ux)"
    [[ -n "${deb}" && -f "${deb}" ]] || die "strawwu-live-install-ux .deb not found"
    cp -f "${deb}" "${ROOTFS_DIR}/tmp/strawwu-live-install-ux.deb"

    deb="$(latest_deb strawwu-calamares-settings)"
    [[ -n "${deb}" && -f "${deb}" ]] || die "strawwu-calamares-settings .deb not found"
    cp -f "${deb}" "${ROOTFS_DIR}/tmp/strawwu-calamares-settings.deb"

    deb="$(latest_deb strawwu-install-init)"
    [[ -n "${deb}" && -f "${deb}" ]] || die "strawwu-install-init .deb not found"
    cp -f "${deb}" "${ROOTFS_DIR}/tmp/strawwu-install-init.deb"
}

install_in_chroot() {
    log "installing target-setup stack inside chroot"
    local inner="${WORK_DIR}/chroot-target-setup-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

need_pkgs=(python3 apt)
missing=()
for pkg in "${need_pkgs[@]}"; do
    dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "ok installed" || missing+=("${pkg}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y --no-install-recommends "${missing[@]}" 2>/dev/null || true
fi

# Resolute live rootfs may lack desktop/IME deps after purge meta restore.
apt-get install -y --no-install-recommends \
    gnome-shell gdm3 session-migration mutter \
    fcitx5 fcitx5-chewing fcitx5-table-cangjie5 \
    fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5 \
    fcitx5-frontend-qt6 fcitx5-module-wayland \
    2>/dev/null || true

# initd must exist before target-setup (Depends).
initd_deb="$(ls -1t /usr/share/strawwu/target-setup/staged-debs/strawwu-initd_*.deb | head -1)"
dpkg -i "${initd_deb}"
dpkg -i /tmp/strawwu-target-setup.deb
rm -f /tmp/strawwu-target-setup.deb

# Live ISO UX + calamares settings (includes target-setup shellprocess hook).
dpkg -i /tmp/strawwu-live-install-ux.deb || apt-get install -f -y
rm -f /tmp/strawwu-live-install-ux.deb
dpkg -i /tmp/strawwu-calamares-settings.deb || apt-get install -f -y
rm -f /tmp/strawwu-calamares-settings.deb
firstboot_deb="$(ls -1t /usr/share/strawwu/target-setup/staged-debs/strawwu-firstboot_*.deb | head -1)"
dpkg -i "${firstboot_deb}" || apt-get install -f -y
dpkg -i /tmp/strawwu-install-init.deb || apt-get install -f -y
rm -f /tmp/strawwu-install-init.deb

command -v strawwu-target-setup >/dev/null
command -v strawwu-initd >/dev/null
test -f /usr/share/strawwu/target-setup/target-manifest.yaml
test -d /usr/share/strawwu/target-setup/staged-debs
test -f /etc/calamares/modules/shellprocess_target-setup.conf
test -f /usr/share/calamares/lang/calamares_zh_TW.qm
test -f /usr/share/calamares/branding/strawwu/lang/calamares-strawwu_zh_TW.qm
test -f /usr/share/strawwu/install-init/install-init-manifest.yaml

# Simulate Calamares chroot target setup on live rootfs.
STRAWWU_TARGET_DEB_DIR=/usr/share/strawwu/target-setup/staged-debs \
    strawwu-target-setup --calamares-chroot

command -v strawwu-session >/dev/null
command -v strawwu-shell >/dev/null
command -v strawwu >/dev/null
strawwu status | grep -qi status
dpkg-query -W -f='${Status}' strawwu-wincompat 2>/dev/null | grep -q "ok installed"
dpkg-query -W -f='${Status}' strawwu-desktop 2>/dev/null | grep -q "ok installed"
dpkg-query -W -f='${Status}' strawwu-update-notifier 2>/dev/null | grep -q "ok installed"
dpkg-query -W -f='${Status}' strawwu-firstboot 2>/dev/null | grep -q "ok installed"
command -v strawwu-firstboot >/dev/null
test -f /etc/xdg/autostart/strawwu-firstboot.desktop
strawwu-initd get lifecycle.target_setup | grep -q done

STRAWWU_TARGET_DEB_DIR=/usr/share/strawwu/target-setup/staged-debs \
    strawwu-target-identity --calamares-chroot --skip-initramfs

command -v strawwu-target-identity >/dev/null
strawwu-initramfs-hooks --skip-initramfs apply
command -v strawwu-initramfs-hooks >/dev/null
test -f /etc/initramfs-tools/conf.d/strawwu-disk-boot
grep -q 'BOOT=local' /etc/initramfs-tools/conf.d/strawwu-disk-boot
dpkg-query -W -f='${Status}' strawwu-initramfs-hooks 2>/dev/null | grep -q "ok installed"
strawwu-initd get lifecycle.initramfs_hooks | grep -q done
test -f /etc/default/grub.d/99-strawwu-identity.cfg
grep -q 'GRUB_DISTRIBUTOR="StrawWU"' /etc/default/grub.d/99-strawwu-identity.cfg
strawwu-initd get lifecycle.target_identity | grep -q done

STRAWWU_TARGET_DEB_DIR=/usr/share/strawwu/target-setup/staged-debs \
    strawwu-disable-upstream-init --calamares-chroot

command -v strawwu-disable-upstream-init >/dev/null
test -f /etc/cloud/cloud-init.disabled
strawwu-initd get lifecycle.upstream_init_disabled | grep -q done

# W6-B5: strawwu-minimal replaces ubuntu-minimal; purge upstream base metas.
minimal_deb="$(ls -1t /usr/share/strawwu/target-setup/staged-debs/strawwu-minimal_*.deb | head -1)"
if [[ -n "${minimal_deb}" && -f "${minimal_deb}" ]]; then
    dpkg -i --force-depends "${minimal_deb}" 2>/dev/null || true
fi
for meta_pkg in ubuntu-minimal ubuntu-standard; do
    if dpkg-query -W -f='${Status}' "${meta_pkg}" 2>/dev/null | grep -q "ok installed"; then
        dpkg --purge --force-depends "${meta_pkg}" 2>/dev/null || apt-get remove -y --purge "${meta_pkg}" 2>/dev/null || true
    fi
done
if dpkg-query -W -f='${Status}' strawwu-minimal 2>/dev/null | grep -q "ok installed"; then
    :
else
    echo "WARN: strawwu-minimal not installed after meta audit step" >&2
fi

# Re-purge telemetry if apt pulled them back during meta operations.
for purge_pkg in apport apport-core-dump-handler python3-apport whoopsie ubuntu-report ubuntu-pro-client ubuntu-pro-client-l10n ubuntu-advantage-desktop-daemon snapd snap-confine; do
    if dpkg-query -W -f='${Status}' "${purge_pkg}" 2>/dev/null | grep -q "ok installed"; then
        dpkg --purge --force-all "${purge_pkg}" 2>/dev/null || apt-get remove -y --purge "${purge_pkg}" 2>/dev/null || true
    fi
done
INNER
    chmod 755 "${inner}"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-target-setup-inner.sh"
    chroot_run /tmp/chroot-target-setup-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-target-setup-inner.sh"
}

sync_squashfs() {
    if [[ ! -d "${SQUASH_SRC}" ]]; then
        log "squashfs-root missing — skipping sync"
        return 0
    fi
    log "syncing rootfs → squashfs-root (target-setup stack)"
    rsync -a \
        "${ROOTFS_DIR}/usr/bin/strawwu-target-setup" \
        "${ROOTFS_DIR}/usr/bin/strawwu-initd" \
        "${ROOTFS_DIR}/usr/bin/strawwu" \
        "${ROOTFS_DIR}/usr/bin/strawwu-session" \
        "${ROOTFS_DIR}/usr/bin/strawwu-shell" \
        "${ROOTFS_DIR}/usr/bin/strawwu-update-notifier" \
        "${ROOTFS_DIR}/usr/bin/strawwu-firstboot" \
        "${ROOTFS_DIR}/usr/bin/strawwu-target-identity" \
        "${ROOTFS_DIR}/usr/bin/strawwu-disable-upstream-init" \
        "${ROOTFS_DIR}/usr/bin/strawwu-greeter" \
        "${SQUASH_SRC}/usr/bin/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/wincompat/" \
        "${SQUASH_SRC}/usr/share/strawwu/wincompat/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-target-setup/" \
        "${SQUASH_SRC}/usr/lib/strawwu-target-setup/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-initd/" \
        "${SQUASH_SRC}/usr/lib/strawwu-initd/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/target-setup/" \
        "${SQUASH_SRC}/usr/share/strawwu/target-setup/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/xsessions/strawwu-session.desktop" \
        "${SQUASH_SRC}/usr/share/xsessions/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/applications/strawwu-install.desktop" \
        "${ROOTFS_DIR}/usr/share/applications/strawwu-firstboot.desktop" \
        "${SQUASH_SRC}/usr/share/applications/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-firstboot/" \
        "${SQUASH_SRC}/usr/lib/strawwu-firstboot/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/firstboot/" \
        "${SQUASH_SRC}/usr/share/strawwu/firstboot/" 2>/dev/null || true
    install -d "${SQUASH_SRC}/usr/share/strawwu/locale"
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/locale/firstboot."*.yaml \
        "${SQUASH_SRC}/usr/share/strawwu/locale/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/etc/xdg/autostart/strawwu-firstboot.desktop" \
        "${SQUASH_SRC}/etc/xdg/autostart/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/etc/calamares/" \
        "${SQUASH_SRC}/etc/calamares/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/calamares/lang/" \
        "${SQUASH_SRC}/usr/share/calamares/lang/" 2>/dev/null || true
    install -d "${SQUASH_SRC}/usr/share/calamares/branding/strawwu/lang"
    rsync -a \
        "${ROOTFS_DIR}/usr/share/calamares/branding/strawwu/lang/" \
        "${SQUASH_SRC}/usr/share/calamares/branding/strawwu/lang/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/install-init/" \
        "${SQUASH_SRC}/usr/share/strawwu/install-init/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-greeter/" \
        "${SQUASH_SRC}/usr/lib/strawwu-greeter/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/greeter/" \
        "${SQUASH_SRC}/usr/share/strawwu/greeter/" 2>/dev/null || true
    install -d "${SQUASH_SRC}/etc/gdm3"
    rsync -a \
        "${ROOTFS_DIR}/etc/gdm3/greeter.dconf-defaults" \
        "${SQUASH_SRC}/etc/gdm3/" 2>/dev/null || true
    install -d "${SQUASH_SRC}/usr/share/gnome-shell/theme"
    rsync -a \
        "${ROOTFS_DIR}/usr/share/gnome-shell/theme/strawwu-greeter.css" \
        "${SQUASH_SRC}/usr/share/gnome-shell/theme/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/gnome-shell/modes/strawwu.json" \
        "${SQUASH_SRC}/usr/share/gnome-shell/modes/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/gnome-shell/extensions/strawwu-dock@strawwu/" \
        "${SQUASH_SRC}/usr/share/gnome-shell/extensions/strawwu-dock@strawwu/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/shell/" \
        "${SQUASH_SRC}/usr/share/strawwu/shell/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-disable-upstream-init/" \
        "${SQUASH_SRC}/usr/lib/strawwu-disable-upstream-init/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/disable-upstream-init/" \
        "${SQUASH_SRC}/usr/share/strawwu/disable-upstream-init/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/etc/cloud/cloud-init.disabled" \
        "${SQUASH_SRC}/etc/cloud/" 2>/dev/null || true
    install -d "${SQUASH_SRC}/etc/dconf/db/local.d"
    rsync -a \
        "${ROOTFS_DIR}/etc/dconf/db/local.d/01-strawwu-no-gnome-initial-setup" \
        "${SQUASH_SRC}/etc/dconf/db/local.d/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/lib/strawwu-target-identity/" \
        "${SQUASH_SRC}/usr/lib/strawwu-target-identity/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/etc/default/grub.d/99-strawwu-identity.cfg" \
        "${SQUASH_SRC}/etc/default/grub.d/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/usr/share/strawwu/target-identity/" \
        "${SQUASH_SRC}/usr/share/strawwu/target-identity/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/var/lib/strawwu/" \
        "${SQUASH_SRC}/var/lib/strawwu/" 2>/dev/null || true
    rsync -a \
        "${ROOTFS_DIR}/var/lib/dpkg/status" \
        "${ROOTFS_DIR}/var/lib/dpkg/status-old" \
        "${ROOTFS_DIR}/var/lib/dpkg/info/" \
        "${SQUASH_SRC}/var/lib/dpkg/" 2>/dev/null || true
}

write_marker() {
    local version="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
    date -Iseconds > "${MARKER}"
    printf '%s\n' "${version}" > "${DEBS_MARKER}"
    log "marker written: ${MARKER} + ${DEBS_MARKER} (v${version})"
}

main() {
    need_root
    verify_prerequisites
    build_debs
    stage_debs
    install_in_chroot
    sync_squashfs
    write_marker
    log "strawwu-target-setup chroot install complete"
}

main "$@"

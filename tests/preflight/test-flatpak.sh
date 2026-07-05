#!/usr/bin/env bash
# W1-F1: Flatpak / Flathub baseline — deb scaffold + rootfs/squashfs state.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== W1-F1 flatpak preflight ==="

require_plan "strawwu-flathub-plan.md"
require_file "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/debian/control" "strawwu-flatpak-setup debian/control"
require_file "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/debian/postinst" "strawwu-flatpak-setup debian/postinst"
require_file "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/build-deb.sh" "strawwu-flatpak-setup build-deb.sh"
require_file "${REPO_ROOT}/os-image/scripts/chroot-install-flatpak-setup.sh" "chroot-install-flatpak-setup.sh"

if [[ ! -x "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/build-deb.sh" ]]; then
    chmod +x "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/build-deb.sh"
    pass "chmod +x build-deb.sh"
fi
if [[ ! -x "${REPO_ROOT}/os-image/scripts/chroot-install-flatpak-setup.sh" ]]; then
    chmod +x "${REPO_ROOT}/os-image/scripts/chroot-install-flatpak-setup.sh"
    pass "chmod +x chroot-install-flatpak-setup.sh"
fi

MARKER="${REPO_ROOT}/os-image/work/.flatpak-setup-ok"
if [[ -f "${MARKER}" ]]; then
    pass "flatpak setup marker present (${MARKER})"
else
    warn "flatpak setup marker missing — run: sudo bash os-image/scripts/chroot-install-flatpak-setup.sh"
fi

if ! has_rootfs && ! has_squashfs; then
    fail "neither rootfs nor squashfs present — run make clone-ubuntu-base first"
fi

check_flatpak_package() {
    local label="$1"
    if package_installed_in_filesystem flatpak; then
        pass "${label} flatpak package installed"
    else
        fail "${label} flatpak package missing"
    fi
}

check_flatpak_cli() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/flatpak" ]]; then
        pass "${label} /usr/bin/flatpak present"
    else
        fail "${label} /usr/bin/flatpak missing"
    fi
}

check_flathub_remote() {
    local root="$1"
    local label="$2"
    if [[ -f "${root}/etc/flatpak/remotes.d/flathub.flatpakrepo" ]]; then
        pass "${label} flathub remote (remotes.d)"
        return 0
    fi
    if [[ -f "${root}/var/lib/flatpak/repo/config" ]] \
        && grep -q '^\[remote "flathub"\]' "${root}/var/lib/flatpak/repo/config" 2>/dev/null; then
        pass "${label} flathub remote (repo config)"
        return 0
    fi
    fail "${label} flathub system remote missing"
}

check_setup_deb() {
    local label="$1"
    if package_installed_in_filesystem strawwu-flatpak-setup; then
        pass "${label} strawwu-flatpak-setup installed"
    else
        fail "${label} strawwu-flatpak-setup missing"
    fi
}

if has_rootfs; then
    check_flatpak_cli "${ROOTFS}" "rootfs"
    check_flatpak_package "rootfs"
    check_setup_deb "rootfs"
    check_flathub_remote "${ROOTFS}" "rootfs"
fi

if has_squashfs; then
    check_flatpak_cli "${SQUASHFS_ROOT}" "squashfs"
    check_flatpak_package "squashfs"
    check_setup_deb "squashfs"
    check_flathub_remote "${SQUASHFS_ROOT}" "squashfs"

    snapd_count="$(count_squashfs_packages '^snapd$')"
    if [[ "${snapd_count}" -gt 0 ]]; then
        warn "squashfs still has snapd (W1-F2 will harden)"
    else
        pass "squashfs snapd absent"
    fi
fi

preflight_exit "W1-F1 flatpak"

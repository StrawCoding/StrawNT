#!/usr/bin/env bash
# build-os-debs.sh — Build all strawwu-* .deb packages under os-image/debs/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEBS_ROOT="${REPO_ROOT}/os-image/debs"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"

# sudo secure_path may omit Rust toolchain (wincompat / desktop-actions).
export PATH="/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Ordered build list (matches chroot-install-target-setup staged packages + keyring).
OS_DEB_PACKAGES=(
    strawwu-initd
    strawwu-wincompat
    strawwu-device-proxy
    strawwu-shell
    strawwu-gtk-theme
    strawwu-icon-theme
    strawwu-session
    strawwu-greeter
    strawwu-update-notifier
    strawwu-upgrade
    strawwu-backup
    strawwu-secureboot
    strawwu-security
    strawwu-software-sources
    strawwu-bug-reporter
    strawwu-drivers
    strawwu-laptop
    strawwu-flatpak-setup
    strawwu-l10n-ime
    strawwu-firstboot
    strawwu-install-init
    strawwu-desktop-actions
    strawwu-registry-hooks
    strawwu-initramfs-hooks
    strawwu-target-identity
    strawwu-disable-upstream-init
    strawwu-minimal
    strawwu-desktop
    strawwu-live-install-ux
    strawwu-target-setup
    strawwu-calamares-settings
    strawwu-keyring
)

deb_arch_suffix() {
    case "$1" in
        strawwu-desktop|strawwu-minimal|strawwu-wincompat) echo amd64 ;;
        *) echo all ;;
    esac
}

expected_deb() {
    local pkg="$1"
    local arch
    arch="$(deb_arch_suffix "${pkg}")"
    echo "${DEBS_ROOT}/${pkg}/output/${pkg}_${VERSION}_${arch}.deb"
}

build_all() {
    local pkg build
    for pkg in "${OS_DEB_PACKAGES[@]}"; do
        build="${DEBS_ROOT}/${pkg}/build-deb.sh"
        [[ -x "${build}" ]] || die "missing build script: ${build}"
        log "building ${pkg} v${VERSION}"
        STRAWWU_VERSION="${VERSION}" bash "${build}"
        [[ -f "$(expected_deb "${pkg}")" ]] || die "artifact missing after build: $(expected_deb "${pkg}")"
    done
    log "all ${#OS_DEB_PACKAGES[@]} os-image debs built for v${VERSION}"
}

main() {
    build_all
}

main "$@"

#!/usr/bin/env bash
# apply-branding.sh — Overlay StrawWU branding into cloned rootfs and ISO staging.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/ubuntu-base-env.sh
source "${SCRIPT_DIR}/lib/ubuntu-base-env.sh"
load_ubuntu_base_env "${REPO_ROOT}"
BRANDING_DIR="${REPO_ROOT}/os-image/config/branding"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
ISO_STAGING="${WORK_DIR}/iso-staging"
read_repo_version() {
    tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo "0.4.0.0"
}
VERSION="${STRAWWU_VERSION:-$(read_repo_version)}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

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
    mount --bind /run  "${ROOTFS_DIR}/run" 2>/dev/null || true
    trap 'unmount_chroot' EXIT
    chroot "${ROOTFS_DIR}" "$@"
    local rc=$?
    unmount_chroot
    trap - EXIT
    return "${rc}"
}

overlay_rootfs() {
    [[ -d "${BRANDING_DIR}" ]] || die "branding dir missing: ${BRANDING_DIR}"
    log "overlaying branding into rootfs"
    cp -a "${BRANDING_DIR}/." "${ROOTFS_DIR}/"
    chmod 755 "${ROOTFS_DIR}/usr/local/sbin/strawwu-boot-selfcheck"
    if [[ -f "${ROOTFS_DIR}/usr/local/sbin/strawwu-rescue-mode" ]]; then
        chmod 755 "${ROOTFS_DIR}/usr/local/sbin/strawwu-rescue-mode"
    fi

    # Version-specific os-release fields (preserve active Ubuntu base from ubuntu-base-target.json)
    local ubuntu_series="${STRAWWU_UBUNTU_VERSION%.*}"
    if [[ -f "${ROOTFS_DIR}/etc/os-release" ]]; then
        sed -i "s/^VERSION=.*/VERSION=\"${VERSION}\"/" "${ROOTFS_DIR}/etc/os-release"
        sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"StrawWU ${VERSION}\"/" "${ROOTFS_DIR}/etc/os-release"
        sed -i "s/^VERSION_ID=.*/VERSION_ID=\"${ubuntu_series}\"/" "${ROOTFS_DIR}/etc/os-release"
        sed -i "s/^VERSION_CODENAME=.*/VERSION_CODENAME=${STRAWWU_APT_SUITE}/" "${ROOTFS_DIR}/etc/os-release"
        if grep -q '^UBUNTU_CODENAME=' "${ROOTFS_DIR}/etc/os-release"; then
            sed -i "s/^UBUNTU_CODENAME=.*/UBUNTU_CODENAME=${STRAWWU_APT_SUITE}/" "${ROOTFS_DIR}/etc/os-release"
        fi
        sed -i "s/^NAME=.*/NAME=\"StrawWU\"/" "${ROOTFS_DIR}/etc/os-release"
    fi
    if [[ -f "${ROOTFS_DIR}/etc/lsb-release" ]]; then
        sed -i "s/^DISTRIB_RELEASE=.*/DISTRIB_RELEASE=${VERSION}/" "${ROOTFS_DIR}/etc/lsb-release"
        sed -i "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION=\"StrawWU ${VERSION}\"/" "${ROOTFS_DIR}/etc/lsb-release"
    fi
}

configure_chroot_branding() {
    log "configuring plymouth + systemd branding in chroot"
    chroot_run update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
        default.plymouth /usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth 200
    chroot_run update-alternatives --set default.plymouth \
        /usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth
    chroot_run plymouth-set-default-theme strawwu-boot 2>/dev/null || true
    chroot_run systemctl enable strawwu-boot-selfcheck.service
    if [[ -f "${ROOTFS_DIR}/etc/systemd/system/strawwu-rescue-mode.service" ]]; then
        chroot_run systemctl enable strawwu-rescue-mode.service
    fi
    if [[ -f "${ROOTFS_DIR}/etc/calamares/settings.conf" ]]; then
        if grep -q '^branding:' "${ROOTFS_DIR}/etc/calamares/settings.conf"; then
            sed -i 's/^branding:.*/branding: strawwu/' "${ROOTFS_DIR}/etc/calamares/settings.conf"
        else
            printf '\nbranding: strawwu\n' >> "${ROOTFS_DIR}/etc/calamares/settings.conf"
        fi
    fi
    log "rebuilding initramfs for plymouth theme (may take a few minutes)"
    chroot_run update-initramfs -u -k all 2>/dev/null || chroot_run update-initramfs -u
}

configure_desktop_theme() {
    log "installing StrawWU desktop theme"

    # Replace Ubuntu distributor-logo in all icon themes that ship one
    local logo_svg="${BRANDING_DIR}/logo-icon.svg"
    if [[ -f "${logo_svg}" ]]; then
        for icon_dir in Humanity Humanity-Dark ubuntu-mono-dark ubuntu-mono-light; do
            local target_base="${ROOTFS_DIR}/usr/share/icons/${icon_dir}"
            [[ -d "${target_base}" ]] || continue
            find "${target_base}" -name 'distributor-logo*' -type f | while read -r f; do
                local ext="${f##*.}"
                if [[ "${ext}" == "svg" ]]; then
                    cp "${logo_svg}" "${f}"
                fi
            done
        done
    fi

    # Replace Ubuntu distributor-logo PNGs at standard sizes
    for size in 48 128 256; do
        local src="${BRANDING_DIR}/logo-icon-${size}.png"
        [[ -f "${src}" ]] || continue
        for icon_dir in Humanity Humanity-Dark; do
            local dst="${ROOTFS_DIR}/usr/share/icons/${icon_dir}/places/${size}/distributor-logo.png"
            [[ -d "$(dirname "${dst}")" ]] && cp "${src}" "${dst}" 2>/dev/null || true
        done
    done

    # Update icon cache for modified icon themes
    for theme in hicolor Humanity Humanity-Dark; do
        local theme_dir="${ROOTFS_DIR}/usr/share/icons/${theme}"
        [[ -d "${theme_dir}" ]] && chroot_run gtk-update-icon-cache -f "/usr/share/icons/${theme}" 2>/dev/null || true
    done

    # Remove SVG source files from rootfs (not needed at runtime)
    rm -f "${ROOTFS_DIR}/usr/share/backgrounds/strawwu/"*.svg 2>/dev/null || true

    log "desktop theme installation complete"
}

patch_user_visible_ubuntu() {
    log "replacing user-visible Ubuntu strings in rootfs"
    local files
    files="$(grep -rl 'Ubuntu' \
        "${ROOTFS_DIR}/etc/issue" \
        "${ROOTFS_DIR}/etc/issue.net" \
        "${ROOTFS_DIR}/etc/motd" \
        "${ROOTFS_DIR}/usr/share/gnome-shell" \
        2>/dev/null || true)"
    if [[ -n "${files}" ]]; then
        # shellcheck disable=SC2086
        sed -i 's/Ubuntu/StrawWU/g' ${files} 2>/dev/null || true
    fi
    if [[ -f "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/10_ubuntu-settings.gschema.override" ]]; then
        sed -i "s|logo='/usr/share/plymouth/ubuntu-logo.png'|logo='/usr/share/plymouth/themes/strawwu-boot/logo.png'|" \
            "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/10_ubuntu-settings.gschema.override" || true
    fi
    if [[ -f "${ROOTFS_DIR}/usr/share/applications/calamares.desktop" ]]; then
        sed -i 's|^Exec=.*|Exec=sh -c "sudo -E calamares -D6"|' \
            "${ROOTFS_DIR}/usr/share/applications/calamares.desktop"
    fi
    chroot_run glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
}

patch_iso_staging() {
    [[ -d "${ISO_STAGING}" ]] || return 0
    log "patching ISO staging boot branding"
    for f in \
        "${ISO_STAGING}/boot/grub/grub.cfg" \
        "${ISO_STAGING}/boot/grub/loopback.cfg" \
        "${ISO_STAGING}/isolinux/txt.cfg" \
        "${ISO_STAGING}/isolinux/grub.cfg"; do
        [[ -f "${f}" ]] || continue
        sed -i \
            -e 's/Try or Install Ubuntu/Try or Install StrawWU/g' \
            -e 's/Ubuntu (safe graphics)/StrawWU (safe graphics)/g' \
            -e 's/Ubuntu/StrawWU/g' \
            "${f}"
    done
    if [[ -f "${ISO_STAGING}/.disk/info" ]]; then
        echo "StrawWU ${VERSION} amd64" > "${ISO_STAGING}/.disk/info"
    fi
    if [[ -f "${ISO_STAGING}/README.diskdefines" ]]; then
        sed -i 's/Ubuntu/StrawWU/g' "${ISO_STAGING}/README.diskdefines" || true
    fi
    if [[ -x "${SCRIPT_DIR}/patch-iso-rescue-entry.sh" ]]; then
        bash "${SCRIPT_DIR}/patch-iso-rescue-entry.sh"
    fi
    if [[ -f "${ISO_STAGING}/casper/initrd" ]]; then
        if [[ -f "${WORK_DIR}/.swap-kernel-ok" ]] && grep -q strawwu-kernel "${WORK_DIR}/.swap-kernel-ok" 2>/dev/null; then
            log "custom kernel detected — casper initrd will be rebuilt in build-iso sync step"
        else
            bash "${SCRIPT_DIR}/repack-initrd-branding.sh"
        fi
    fi
}

apply_rootfs_branding() {
    [[ -d "${ROOTFS_DIR}" ]] || die "rootfs missing: ${ROOTFS_DIR}"
    overlay_rootfs
    patch_user_visible_ubuntu
    configure_desktop_theme
    configure_chroot_branding
}

main() {
    local mode="${1:-rootfs}"
    case "${mode}" in
        rootfs) apply_rootfs_branding ;;
        iso) patch_iso_staging ;;
        all)
            apply_rootfs_branding
            patch_iso_staging
            ;;
        *) die "usage: $0 [rootfs|iso|all]" ;;
    esac
    log "branding apply complete (${mode})"
}

main "$@"

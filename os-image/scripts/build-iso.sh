#!/usr/bin/env bash
# build-iso.sh — Repack cloned Ubuntu rootfs into StrawWU live ISO via xorriso.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
OUTPUT_DIR="${REPO_ROOT}/os-image/output"
ISO_CACHE="${OUTPUT_DIR}/cache"
ISO_STAGING="${WORK_DIR}/iso-staging"
ISO_MOUNT="${WORK_DIR}/iso-mount"

UBUNTU_VERSION="${STRAWWU_UBUNTU_VERSION:-24.04.2}"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
VERSION="${STRAWWU_VERSION:-0.3.0-cleanroom}"
ISO_NAME="StrawWU-${VERSION}-amd64.iso"
ISO_PATH="${OUTPUT_DIR}/${ISO_NAME}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root"
}

need_cmd() {
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c"; done
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
    mount --bind /run  "${ROOTFS_DIR}/run" 2>/dev/null || true
    trap 'unmount_chroot' EXIT
    chroot "${ROOTFS_DIR}" "$@"
    local rc=$?
    unmount_chroot
    trap - EXIT
    return "${rc}"
}

patch_boot_serial_console() {
    local console_args="console=ttyS0,115200n8"
    local cfg
    for cfg in \
        "${ISO_STAGING}/boot/grub/grub.cfg" \
        "${ISO_STAGING}/boot/grub/loopback.cfg" \
        "${ISO_STAGING}/isolinux/txt.cfg"; do
        [[ -f "${cfg}" ]] || continue
        log "patching serial console into ${cfg}"
        sed -i "/^[[:space:]]*linux[[:space:]]/ s/$/ ${console_args}/" "${cfg}"
        sed -i "/^[[:space:]]*append[[:space:]]/ s/$/ ${console_args}/" "${cfg}"
    done
}

inject_boot_marker() {
    log "injecting STRAWWU_BOOT_OK serial marker service"
    mkdir -p "${ROOTFS_DIR}/etc/systemd/system"
    cat > "${ROOTFS_DIR}/etc/systemd/system/strawwu-boot-marker.service" <<'EOF'
[Unit]
Description=StrawWU boot test serial marker
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'K=$(uname -r); for i in 1 2 3 4 5 6 7 8 9 10; do if [ -c /dev/ttyS0 ]; then echo STRAWWU_BOOT_OK > /dev/ttyS0; echo "STRAWWU_KERNEL_${K}" > /dev/ttyS0; exit 0; fi; sleep 1; done; exit 1'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    chroot_run systemctl enable strawwu-boot-marker.service
}

apply_branding() {
    STRAWWU_VERSION="${VERSION}" bash "${SCRIPT_DIR}/apply-branding.sh" rootfs
}

resolve_source_iso() {
  if [[ -f "${WORK_DIR}/.source-iso-path" ]]; then
        cat "${WORK_DIR}/.source-iso-path"
        return
    fi
    echo "${ISO_CACHE}/${UBUNTU_ISO_NAME}"
}

iso_layout() {
    if [[ -f "${WORK_DIR}/.iso-layout" ]]; then
        cat "${WORK_DIR}/.iso-layout"
    else
        echo "monolithic"
    fi
}

stage_iso_tree() {
    local source_iso="$1"
    local layout
    layout="$(iso_layout)"
    log "staging ISO tree from ${source_iso} (layout=${layout})"
    rm -rf "${ISO_STAGING}"
    mkdir -p "${ISO_STAGING}"

    if mountpoint -q "${ISO_MOUNT}" 2>/dev/null; then
        umount "${ISO_MOUNT}" || true
    fi
    mkdir -p "${ISO_MOUNT}"
    mount -o loop,ro "${source_iso}" "${ISO_MOUNT}"
    trap 'umount "${ISO_MOUNT}" 2>/dev/null || true' RETURN

    if command -v rsync >/dev/null 2>&1; then
        if [[ "${layout}" == "layered" ]]; then
            # Noble live boot needs casper/minimal*.squashfs — keep upstream layers.
            rsync -a --exclude='casper/filesystem.squashfs' "${ISO_MOUNT}/" "${ISO_STAGING}/"
        else
            rsync -a \
                --exclude='casper/filesystem.squashfs' \
                --exclude='casper/minimal*.squashfs' \
                "${ISO_MOUNT}/" "${ISO_STAGING}/"
        fi
    else
        cp -a "${ISO_MOUNT}/." "${ISO_STAGING}/"
        rm -f "${ISO_STAGING}"/casper/filesystem.squashfs
        if [[ "${layout}" != "layered" ]]; then
            rm -f "${ISO_STAGING}"/casper/minimal*.squashfs
        fi
    fi

    umount "${ISO_MOUNT}"
    trap - RETURN
}

write_layer_size() {
    local squash="$1"
    local size_file="$2"
    local size
    size="$(du -sb "${squash}" | cut -f1)"
    echo -n "${size}" > "${size_file}"
}

make_empty_layer() {
    local out="$1"
    local tmp="${WORK_DIR}/.empty-layer"
    rm -rf "${tmp}"
    mkdir -p "${tmp}"
    mksquashfs "${tmp}" "${out}" -comp zstd -noappend -processors 1
    rm -rf "${tmp}"
}

rebuild_squashfs_layered() {
    local base_out="${ISO_STAGING}/casper/minimal.squashfs"
    local standard_out="${ISO_STAGING}/casper/minimal.standard.squashfs"
    local lang_out="${ISO_STAGING}/casper/minimal.en.squashfs"
    local lang_alt="${ISO_STAGING}/casper/minimal.no-languages.squashfs"

    log "layered ISO: repacking merged rootfs into minimal.squashfs (+ empty overlay stubs)"
    rm -f "${ISO_STAGING}/casper/filesystem.squashfs"
    mksquashfs "${ROOTFS_DIR}" "${base_out}" -comp zstd -noappend -e boot -processors "${STRAWWU_MKSQUASHFS_PROCESSORS:-4}"
    make_empty_layer "${standard_out}"
    if [[ -f "${lang_out}" || -f "${lang_alt}" ]]; then
        if [[ -f "${lang_out}" ]]; then
            make_empty_layer "${lang_out}"
        else
            make_empty_layer "${lang_alt}"
        fi
    fi

    write_layer_size "${base_out}" "${ISO_STAGING}/casper/minimal.size"
    write_layer_size "${standard_out}" "${ISO_STAGING}/casper/minimal.standard.size"
    if [[ -f "${lang_out}" ]]; then
        write_layer_size "${lang_out}" "${ISO_STAGING}/casper/minimal.en.size"
    elif [[ -f "${lang_alt}" ]]; then
        write_layer_size "${lang_alt}" "${ISO_STAGING}/casper/minimal.no-languages.size"
    fi

    unmount_chroot
    chroot_run dpkg-query -W -f '${Package} ${Version}\n' > "${ISO_STAGING}/casper/minimal.manifest" 2>/dev/null \
        || true
    log "layered squashfs repack complete"
}

write_install_sources() {
    [[ "$(iso_layout)" == "layered" ]] && return 0
    unmount_chroot
    local size
    size="$(du -sb "${ROOTFS_DIR}" 2>/dev/null | cut -f1)"
    cat > "${ISO_STAGING}/casper/install-sources.yaml" <<EOF
- default: true
  description:
    en: StrawWU Desktop (${VERSION})
  id: strawwu-desktop
  locale_support: langpack
  name:
    en: StrawWU Desktop
  path: filesystem.squashfs
  size: ${size}
  type: fsimage
  variant: desktop
EOF
}

rebuild_squashfs() {
    [[ -d "${ISO_STAGING}/casper" ]] || die "casper/ not found in staged ISO"

    if [[ "$(iso_layout)" == "layered" ]]; then
        rebuild_squashfs_layered
        return 0
    fi

    local squash_out="${ISO_STAGING}/casper/filesystem.squashfs"

    if [[ -f "${squash_out}" && "${STRAWWU_SKIP_SQUASHFS:-0}" == "1" ]]; then
        log "STRAWWU_SKIP_SQUASHFS=1: reusing ${squash_out}"
    else
        log "mksquashfs → ${squash_out}"
        rm -f "${squash_out}"
        mksquashfs "${ROOTFS_DIR}" "${squash_out}" -comp zstd -noappend -e boot -processors "${STRAWWU_MKSQUASHFS_PROCESSORS:-4}"
    fi

    unmount_chroot
    local size
    size="$(du -sx --block-size=1 "${ROOTFS_DIR}" 2>/dev/null | cut -f1)"
    echo -n "${size}" > "${ISO_STAGING}/casper/filesystem.size"
    chroot_run dpkg-query -W -f '${Package} ${Version}\n' > "${ISO_STAGING}/casper/filesystem.manifest" 2>/dev/null \
        || true
    log "filesystem.size=${size}"
    write_install_sources
}

sync_casper_kernel() {
    local marker="${WORK_DIR}/.swap-kernel-ok"
    [[ -f "${marker}" ]] || return 0
    grep -q strawwu-kernel "${marker}" 2>/dev/null || return 0

    local vmlinuz initrd
    vmlinuz="$(ls "${ROOTFS_DIR}/boot/vmlinuz-"* 2>/dev/null | head -1)"
    initrd="$(ls "${ROOTFS_DIR}/boot/initrd.img-"* 2>/dev/null | head -1)"
    [[ -f "${vmlinuz}" ]] || die "custom kernel vmlinuz missing in rootfs /boot after swap"
    [[ -f "${initrd}" ]] || die "custom kernel initrd missing in rootfs /boot after swap"
    log "syncing casper vmlinuz/initrd from $(basename "${vmlinuz}")"
    cp -f "${vmlinuz}" "${ISO_STAGING}/casper/vmlinuz"
    cp -f "${initrd}" "${ISO_STAGING}/casper/initrd"
}

xorriso_repack() {
    local source_iso="$1"
    log "xorriso repack (as_mkisofs) → ${ISO_PATH}"
    rm -f "${ISO_PATH}"

    local report_file="${WORK_DIR}/xorriso-report.txt"
    xorriso -indev "${source_iso}" -report_el_torito as_mkisofs > "${report_file}" 2>/dev/null \
        || die "xorriso report_el_torito failed"

    local mkisofs_cmd
    mkisofs_cmd="$(
        grep -v '^--modification-date' "${report_file}" \
            | sed "s|${source_iso}|${ISO_STAGING}|g; s/^-V.*/-V 'StrawWU ${VERSION}'/" \
            | tr '\n' ' '
    )"

    # shellcheck disable=SC2086
    eval xorriso -as mkisofs ${mkisofs_cmd} -o "\"${ISO_PATH}\"" "\"${ISO_STAGING}\"" \
        2>"${WORK_DIR}/xorriso-mkisofs.log" \
        || die "xorriso as_mkisofs failed (see ${WORK_DIR}/xorriso-mkisofs.log)"
    [[ -f "${ISO_PATH}" ]] || die "ISO not created: ${ISO_PATH}"
    xorriso -indev "${ISO_PATH}" -report_el_torito plain >/dev/null 2>&1 \
        || die "repacked ISO missing El Torito boot"
}

write_checksums() {
    log "writing SHA256SUMS"
    (
        cd "${OUTPUT_DIR}"
        sha256sum "${ISO_NAME}" > SHA256SUMS
    )
    cat "${OUTPUT_DIR}/SHA256SUMS"
}

main() {
    need_root
    need_cmd mksquashfs xorriso mount umount du sed dpkg-query

    [[ -f "${WORK_DIR}/.clone-ubuntu-base-ok" ]] || die "run make clone-ubuntu-base first"
    [[ -d "${ROOTFS_DIR}" ]] || die "rootfs missing: ${ROOTFS_DIR}"

    bash "${SCRIPT_DIR}/swap-kernel.sh"
    apply_branding
    inject_boot_marker

    local source_iso
    source_iso="$(resolve_source_iso)"
    [[ -f "${source_iso}" ]] || die "source ISO not found: ${source_iso}"

    mkdir -p "${OUTPUT_DIR}"
    stage_iso_tree "${source_iso}"
    patch_boot_serial_console
    STRAWWU_VERSION="${VERSION}" bash "${SCRIPT_DIR}/apply-branding.sh" iso
    rebuild_squashfs
    sync_casper_kernel
    xorriso_repack "${source_iso}"
    write_checksums

    date -Is > "${WORK_DIR}/.build-iso-ok"
    log "build complete: ${ISO_PATH}"
}

main "$@"

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
    # casper bind-mounts need empty mount points in the squashfs overlay root
    mkdir -p "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run"
    chmod 755 "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run"
}

prepare_squashfs_mount_points() {
    unmount_chroot
    mknod -m 666 "${ROOTFS_DIR}/dev/null" c 1 3 2>/dev/null || true
    mknod -m 666 "${ROOTFS_DIR}/dev/zero" c 1 5 2>/dev/null || true
    mknod -m 666 "${ROOTFS_DIR}/dev/random" c 1 8 2>/dev/null || true
    mknod -m 666 "${ROOTFS_DIR}/dev/urandom" c 1 9 2>/dev/null || true
    mknod -m 600 "${ROOTFS_DIR}/dev/console" c 5 1 2>/dev/null || true
    mknod -m 666 "${ROOTFS_DIR}/dev/tty" c 5 0 2>/dev/null || true
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
    # tty0 = physical display (Plymouth + framebuffer); ttyS0 = QEMU serial boot-test marker
    # username=ubuntu keeps casper live user stable when .disk/info starts with "StrawWU"
    local console_args="console=tty0 console=ttyS0,115200n8 username=ubuntu"
    local cfg
    for cfg in \
        "${ISO_STAGING}/boot/grub/grub.cfg" \
        "${ISO_STAGING}/boot/grub/loopback.cfg" \
        "${ISO_STAGING}/isolinux/txt.cfg"; do
        [[ -f "${cfg}" ]] || continue
        log "patching console (tty0 + serial) into ${cfg}"
        sed -i 's/ console=ttyS0,115200n8//g' "${cfg}"
        sed -i 's/ console=tty0//g' "${cfg}"
        sed -i 's/ username=ubuntu//g' "${cfg}"
        sed -i "/^[[:space:]]*linux[[:space:]]/ s/$/ ${console_args}/" "${cfg}"
        sed -i "/^[[:space:]]*append[[:space:]]/ s/$/ ${console_args}/" "${cfg}"
    done
    # Upstream noble grub.cfg has a bare "grub_platform" line that UEFI grub treats as a command.
    if [[ -f "${ISO_STAGING}/boot/grub/grub.cfg" ]]; then
        sed -i '/^grub_platform$/d' "${ISO_STAGING}/boot/grub/grub.cfg"
    fi
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

    if [[ -f "${ISO_STAGING}/casper/initrd" && ! -f "${ISO_STAGING}/casper/initrd.ubuntu-backup" ]]; then
        cp -a "${ISO_STAGING}/casper/initrd" "${ISO_STAGING}/casper/initrd.ubuntu-backup"
        log "saved casper/initrd.ubuntu-backup from upstream ISO"
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

squashfs_exclude_args="-e boot"

rebuild_squashfs_layered() {
    if [[ "${STRAWWU_SKIP_SQUASHFS:-0}" == "1" ]]; then
        log "STRAWWU_SKIP_SQUASHFS=1: reusing layered casper squashfs"
        return 0
    fi
    local base_out="${ISO_STAGING}/casper/minimal.squashfs"
    local standard_out="${ISO_STAGING}/casper/minimal.standard.squashfs"
    local lang_out="${ISO_STAGING}/casper/minimal.en.squashfs"
    local lang_alt="${ISO_STAGING}/casper/minimal.no-languages.squashfs"

    log "layered ISO: repacking merged rootfs into minimal.squashfs (+ empty overlay stubs)"
    prepare_squashfs_mount_points
    rm -f "${ISO_STAGING}/casper/filesystem.squashfs"
    # Upstream rsync leaves casper/*.squashfs read-only; mksquashfs must replace, not append.
    rm -f "${base_out}" "${standard_out}" "${lang_out}" "${lang_alt}"
    mksquashfs "${ROOTFS_DIR}" "${base_out}" -comp zstd -noappend ${squashfs_exclude_args} -processors "${STRAWWU_MKSQUASHFS_PROCESSORS:-4}"
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
        prepare_squashfs_mount_points
        rm -f "${squash_out}"
        mksquashfs "${ROOTFS_DIR}" "${squash_out}" -comp zstd -noappend ${squashfs_exclude_args} -processors "${STRAWWU_MKSQUASHFS_PROCESSORS:-4}"
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

repack_initrd_phases() {
    local initrd_src="$1"
    local initrd_out="$2"
    local scratch="$3"
    local kver="${4:-}"
    local modules_src="${5:-}"
    local splice="${SCRIPT_DIR}/initrd-splice.py"
    local branding_dir="${REPO_ROOT}/os-image/config/branding"
    local extra=()

    [[ -f "${splice}" ]] || die "initrd splice helper missing: ${splice}"
    if [[ -n "${kver}" && -d "${modules_src}" ]]; then
        extra=(--modules-src "${modules_src}" --new-kver "${kver}" --preserve-main --branding-root "${branding_dir}")
        log "repacking initrd: early3 modules + plymouth in early3+main, preserve upstream main structure for ${kver}"
    fi
    python3 "${splice}" repack-main-only "${initrd_src}" /dev/null "${initrd_out}" "${scratch}" "${extra[@]}"
}

inject_plymouth_into_initrd_main() {
    local target="$1"
    local branding_dir="${REPO_ROOT}/os-image/config/branding"
    local theme_src="${branding_dir}/usr/share/plymouth/themes/strawwu-boot"
    local plymouth_conf="${branding_dir}/etc/plymouth/plymouthd.conf"

    [[ -d "${theme_src}" ]] || die "plymouth theme missing: ${theme_src}"
    mkdir -p "${target}/usr/share/plymouth/themes/strawwu-boot"
    cp -a "${theme_src}/." "${target}/usr/share/plymouth/themes/strawwu-boot/"
    mkdir -p "${target}/etc/plymouth"
    cp -a "${plymouth_conf}" "${target}/etc/plymouth/plymouthd.conf"
    ln -sf /usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth \
        "${target}/usr/share/plymouth/themes/default.plymouth"
    if [[ -f "${target}/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth" ]]; then
        sed -i 's/^title=.*/title=StrawWU/' \
            "${target}/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth" || true
    fi
}

patch_casper_conf_in_initrd() {
    local target="$1"
    local conf="${target}/etc/casper.conf"
    [[ -f "${conf}" ]] || return 0
    # Keep live user ubuntu; .disk/info "StrawWU ..." would otherwise set USERNAME=strawwu.
    sed -i \
        -e 's/^export BUILD_SYSTEM=.*/export BUILD_SYSTEM="StrawWU"/' \
        -e 's/^export USERFULLNAME=.*/export USERFULLNAME="StrawWU Live session user"/' \
        -e 's/^# export FLAVOUR=.*/export FLAVOUR="StrawWU"/' \
        -e 's/^export FLAVOUR=.*/export FLAVOUR="StrawWU"/' \
        "${conf}"
    if ! grep -q '^export FLAVOUR=' "${conf}"; then
        printf '\nexport FLAVOUR="StrawWU"\n' >> "${conf}"
    fi
}

initrd_modules_dir() {
    local root="$1"
    if [[ -d "${root}/usr/lib/modules" ]]; then
        echo "usr/lib/modules"
    elif [[ -d "${root}/lib/modules" ]]; then
        echo "lib/modules"
    else
        echo ""
    fi
}

merge_rootfs_initrd_modules() {
    local target="$1"
    local kver="$2"
    local rootfs_initrd="${ROOTFS_DIR}/boot/initrd.img-${kver}"
    local scratch="${WORK_DIR}/initrd-rootfs-modules"
    local rel modules_rel src_mods

    [[ -f "${rootfs_initrd}" ]] || return 1
    modules_rel="$(initrd_modules_dir "${target}")"
    [[ -n "${modules_rel}" ]] || return 1

    log "merging ${kver} modules from rootfs initrd into casper initrd"
    rm -rf "${scratch}"
    mkdir -p "${scratch}"
    unmkinitramfs "${rootfs_initrd}" "${scratch}" 2>/dev/null || return 1

    src_mods="$(initrd_modules_dir "${scratch}/main")"
    [[ -n "${src_mods}" && -d "${scratch}/main/${src_mods}/${kver}" ]] || {
        rm -rf "${scratch}"
        return 1
    }

    rm -rf "${target}/${modules_rel}"
    mkdir -p "${target}/${modules_rel}"
    cp -a "${scratch}/main/${src_mods}/${kver}" "${target}/${modules_rel}/"
    rm -rf "${scratch}"
    return 0
}

rebuild_casper_initrd() {
    local kver="${1:-}"
    local initrd="${ISO_STAGING}/casper/initrd"
    local initrd_src="${ISO_STAGING}/casper/initrd.ubuntu-backup"
    local modules_src=""
    local scratch="${WORK_DIR}/initrd-rebuild"

    [[ -f "${initrd_src}" ]] || initrd_src="${ISO_STAGING}/casper/initrd"
    [[ -f "${initrd_src}" ]] || die "casper initrd missing in ISO staging"

    log "rebuilding casper initrd from $(basename "${initrd_src}") (preserve main.zst devnodes)"
    rm -rf "${scratch}"
    mkdir -p "${scratch}"

    if [[ -n "${kver}" ]]; then
        modules_src="${ROOTFS_DIR}/lib/modules/${kver}"
        [[ -d "${modules_src}" ]] || die "kernel modules missing: ${modules_src}"
    fi

    repack_initrd_phases "${initrd_src}" "${initrd}" "${scratch}/splice" "${kver}" "${modules_src}"
    python3 "${SCRIPT_DIR}/initrd-splice.py" verify "${initrd}" >&2 || log "warning: unmkinitramfs verify failed (expected when main preserved)"
    log "casper initrd rebuilt ($(du -h "${initrd}" | cut -f1))"
}

sync_casper_initrd_modules() {
    local kver="$1"
    rebuild_casper_initrd "${kver}"
}

sync_casper_kernel() {
    local marker="${WORK_DIR}/.swap-kernel-ok"
    [[ -f "${marker}" ]] || return 0
    grep -q strawwu-kernel "${marker}" 2>/dev/null || return 0

    local vmlinuz kver
    vmlinuz="$(ls "${ROOTFS_DIR}/boot/vmlinuz-"* 2>/dev/null | head -1)"
    [[ -f "${vmlinuz}" ]] || die "custom kernel vmlinuz missing in rootfs /boot after swap"
    kver="$(basename "${vmlinuz}" | sed 's/^vmlinuz-//')"
    log "syncing casper vmlinuz from ${kver} (preserving casper initrd, injecting modules)"
    cp -f "${vmlinuz}" "${ISO_STAGING}/casper/vmlinuz"
    sync_casper_initrd_modules "${kver}"
}

wait_for_stable_file() {
    local f="$1"
    local last="" size stable=0 i
    [[ -f "${f}" ]] || return 0
    for i in $(seq 1 30); do
        size="$(stat -c%s "${f}" 2>/dev/null || echo 0)"
        if [[ "${size}" == "${last}" && "${size}" -gt 0 ]]; then
            stable=$((stable + 1))
            [[ "${stable}" -ge 2 ]] && return 0
        else
            stable=0
            last="${size}"
        fi
        sleep 2
    done
    log "warning: ${f} may still be changing before xorriso"
}

xorriso_repack() {
    local source_iso="$1"
    log "xorriso repack (as_mkisofs) → ${ISO_PATH}"
    rm -f "${ISO_PATH}"
    wait_for_stable_file "${ISO_STAGING}/casper/minimal.squashfs"
    wait_for_stable_file "${ISO_STAGING}/casper/initrd"

    local report_file="${WORK_DIR}/xorriso-report.txt"
    xorriso -indev "${source_iso}" -report_el_torito as_mkisofs > "${report_file}" 2>/dev/null \
        || die "xorriso report_el_torito failed"

    # Preserve --interval:... paths that read binary slices (MBR, appended ESP)
    # from the upstream ISO; replacing them with ISO_STAGING breaks UEFI boot.
    local mkisofs_cmd
    mkisofs_cmd="$(
        grep -v '^--modification-date' "${report_file}" \
            | while IFS= read -r line || [[ -n "${line}" ]]; do
                if [[ "${line}" == *"--interval:"* ]]; then
                    printf '%s\n' "${line}"
                elif [[ "${line}" =~ ^-V ]]; then
                    printf "%s\n" "-V 'StrawWU ${VERSION}'"
                else
                    printf '%s\n' "${line}" | sed "s|${source_iso}|${ISO_STAGING}|g"
                fi
            done | tr '\n' ' '
    )"

    # shellcheck disable=SC2086
    eval xorriso -return_with SORRY 32 0 -as mkisofs ${mkisofs_cmd} -o "\"${ISO_PATH}\"" "\"${ISO_STAGING}\"" \
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

    local kernel_deb="${STRAWWU_KERNEL_DEB:-}"
    if [[ -z "${kernel_deb}" && -f "${REPO_ROOT}/kernel/output/.kernel-deb-path" ]]; then
        kernel_deb="$(cat "${REPO_ROOT}/kernel/output/.kernel-deb-path")"
    fi
    if [[ -z "${kernel_deb}" ]]; then
        kernel_deb="$(find "${REPO_ROOT}/kernel/output" -maxdepth 1 -name 'linux-image-strawwu_*.deb' 2>/dev/null | head -1)"
    fi
    STRAWWU_KERNEL_DEB="${kernel_deb}" bash "${SCRIPT_DIR}/swap-kernel.sh"
    apply_branding
    inject_boot_marker

    local source_iso
    source_iso="$(resolve_source_iso)"
    [[ -f "${source_iso}" ]] || die "source ISO not found: ${source_iso}"

    mkdir -p "${OUTPUT_DIR}"
    stage_iso_tree "${source_iso}"
    STRAWWU_VERSION="${VERSION}" bash "${SCRIPT_DIR}/apply-branding.sh" iso
    patch_boot_serial_console
    unmount_chroot
    rebuild_squashfs
    sync_casper_kernel
    xorriso_repack "${source_iso}"
    write_checksums

    date -Is > "${WORK_DIR}/.build-iso-ok"
    log "build complete: ${ISO_PATH}"
}

main "$@"

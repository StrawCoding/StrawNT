#!/usr/bin/env bash
# build-iso.sh — Repack cloned Ubuntu rootfs into StrawWU live ISO via xorriso.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/ubuntu-base-env.sh
source "${SCRIPT_DIR}/lib/ubuntu-base-env.sh"
# shellcheck source=lib/base-marker.sh
source "${SCRIPT_DIR}/lib/base-marker.sh"
load_ubuntu_base_env "${REPO_ROOT}"
read_repo_version() {
    tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo "0.4.0.0"
}
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
OUTPUT_DIR="${REPO_ROOT}/os-image/output"
ISO_CACHE="${OUTPUT_DIR}/cache"
ISO_STAGING="${WORK_DIR}/iso-staging"
ISO_MOUNT="${WORK_DIR}/iso-mount"

UBUNTU_VERSION="${STRAWWU_UBUNTU_VERSION}"
UBUNTU_ISO_NAME="${STRAWWU_UBUNTU_ISO_NAME}"
VERSION="${STRAWWU_VERSION:-$(read_repo_version)}"
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
        sed -i 's/ boot=casper//g' "${cfg}"
        # boot=casper must precede '---' (kernel args); missing on UEFI breaks live-media scan.
        sed -i '/^[[:space:]]*linux[[:space:]]/ s|\(/casper/vmlinuz\)[[:space:]]*|\1 boot=casper |' "${cfg}"
        sed -i "/^[[:space:]]*append[[:space:]]/ s/^/boot=casper /" "${cfg}"
        sed -i "/^[[:space:]]*linux[[:space:]]/ s/$/ ${console_args}/" "${cfg}"
        sed -i "/^[[:space:]]*append[[:space:]]/ s/$/ ${console_args}/" "${cfg}"
        # Upstream noble grub has a bare "grub_platform" line UEFI grub treats as a command.
        sed -i '/^grub_platform$/d' "${cfg}"
    done
}

force_gdm_x11() {
    [[ "${STRAWWU_FORCE_X11:-0}" == "1" ]] || return 0
    log "forcing GDM to use X11 (STRAWWU_FORCE_X11=1 — install-e2e only)"
    local conf="${ROOTFS_DIR}/etc/gdm3/custom.conf"
    if [[ -f "${conf}" ]]; then
        sed -i 's/^#\?WaylandEnable=.*$/WaylandEnable=false/' "${conf}"
        if ! grep -q '^WaylandEnable=false' "${conf}"; then
            sed -i '/^\[daemon\]/a WaylandEnable=false' "${conf}"
        fi
    fi
}

configure_live_autologin() {
    [[ "${STRAWWU_ENABLE_E2E:-0}" == "1" ]] && return 0
    log "enabling casper live autologin for ubuntu user"
    local conf="${ROOTFS_DIR}/etc/gdm3/custom.conf"
    [[ -f "${conf}" ]] || return 0
    if grep -qE '^#?[[:space:]]*AutomaticLoginEnable' "${conf}"; then
        sed -i 's/^#\?[[:space:]]*AutomaticLoginEnable.*/AutomaticLoginEnable = true/' "${conf}"
    else
        sed -i '/^\[daemon\]/a AutomaticLoginEnable = true' "${conf}"
    fi
    if grep -qE '^#?[[:space:]]*AutomaticLogin[[:space:]]*=' "${conf}"; then
        sed -i 's/^#\?[[:space:]]*AutomaticLogin[[:space:]]*=.*/AutomaticLogin = ubuntu/' "${conf}"
    else
        sed -i '/^\[daemon\]/a AutomaticLogin = ubuntu' "${conf}"
    fi
}

inject_boot_marker() {
    log "injecting STRAWWU_BOOT_OK serial marker service"
    mkdir -p "${ROOTFS_DIR}/etc/systemd/system"
    cat > "${ROOTFS_DIR}/etc/systemd/system/strawwu-boot-marker.service" <<'EOF'
[Unit]
Description=StrawWU boot test serial marker
DefaultDependencies=no
After=gdm.service plymouth-quit-wait.service
Wants=gdm.service

[Service]
Type=oneshot
# GDM up = live session ready; tee to serial + console (do not require -c ttyS0 — casper overlay may lag).
ExecStart=/bin/sh -c 'K=$(uname -r); { echo STRAWWU_BOOT_OK; echo STRAWWU-DESKTOP-OK; echo "STRAWWU_KERNEL_${K}"; } | tee /dev/ttyS0 /dev/console /dev/kmsg >/dev/null 2>&1 || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    chroot_run systemctl enable strawwu-boot-marker.service

    log "injecting W8 HW matrix probe serial markers"
    cat > "${ROOTFS_DIR}/etc/systemd/system/strawwu-hw-matrix-probe.service" <<'EOF'
[Unit]
Description=StrawWU HW matrix probe (GPU/Wi-Fi/suspend/HiDPI)
DefaultDependencies=no
After=network-online.target gdm.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '\
  M=""; \
  systemctl is-active network-online.target >/dev/null 2>&1 && M="${M} STRAWWU-NET-OK"; \
  [ -e /dev/dri/card0 ] && M="${M} STRAWWU-GPU-OK"; \
  busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspend 2>/dev/null | grep -q yes && M="${M} STRAWWU-SUSPEND-PROBE-OK"; \
  command -v gsettings >/dev/null 2>&1 && M="${M} STRAWWU-HIDPI-PROBE-OK"; \
  [ -n "$M" ] && echo $M | tee /dev/ttyS0 /dev/console /dev/kmsg >/dev/null 2>&1 || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    chroot_run systemctl enable strawwu-hw-matrix-probe.service
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
    run_mksquashfs "${tmp}" "${out}"
    rm -rf "${tmp}"
}

squashfs_exclude_args="-e boot"

run_mksquashfs() {
    local src="$1" dest="$2"
    local -a comp_args=()
    iso_mode_squashfs_args comp_args
    log "mksquashfs ${dest} mode=${STRAWWU_ISO_MODE} comp=${STRAWWU_MKSQUASHFS_COMP[0]}"
    mksquashfs "${src}" "${dest}" "${comp_args[@]}" ${squashfs_exclude_args}
}

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
    run_mksquashfs "${ROOTFS_DIR}" "${base_out}"
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
        run_mksquashfs "${ROOTFS_DIR}" "${squash_out}"
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
    vmlinuz="$(ls "${ROOTFS_DIR}/boot/vmlinuz-"*strawwu* 2>/dev/null | head -1)"
    if [[ -z "${vmlinuz}" ]]; then
        vmlinuz="$(ls "${ROOTFS_DIR}/boot/vmlinuz-"* 2>/dev/null | head -1)"
    fi
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
    # Use a bash array — eval + unquoted word-split breaks multi-token lines
    # (-append_partition, -e '--interval:...') and passes them as one option.
    normalize_interval_token() {
        local token="$1"
        # xorriso report wraps paths in single quotes inside interval specs.
        token="${token//\'/}"
        printf '%s' "${token}"
    }

    strip_shell_quotes() {
        local s="$1"
        if [[ "${s}" == \'*\' || "${s}" == \"*\" ]]; then
            s="${s:1:${#s}-2}"
        fi
        printf '%s' "${s}"
    }

    local -a mkisofs_args=()
    local line parts interval
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^--modification-date ]] && continue
        if [[ "${line}" =~ ^-V ]]; then
            mkisofs_args+=(-V "StrawWU ${VERSION}")
            continue
        fi
        if [[ "${line}" == *"--grub2-mbr"* && "${line}" == *" --interval:"* ]]; then
            interval="$(normalize_interval_token "${line#*--grub2-mbr }")"
            mkisofs_args+=(--grub2-mbr "${interval}")
            continue
        fi
        if [[ "${line}" == -append_partition\ * && "${line}" == *" --interval:"* ]]; then
            read -r -a parts <<< "${line}"
            parts[3]="$(normalize_interval_token "${parts[3]}")"
            mkisofs_args+=("${parts[@]}")
            continue
        fi
        if [[ "${line}" =~ ^-e[[:space:]] ]]; then
            interval="$(normalize_interval_token "${line#-e }")"
            mkisofs_args+=(-e "${interval}")
            continue
        fi
        if [[ "${line}" =~ ^-(b|c)[[:space:]] ]]; then
            read -r -a parts <<< "${line}"
            mkisofs_args+=("${parts[0]}" "$(strip_shell_quotes "${parts[1]}")")
            continue
        fi
        # genisoimage-only partition tuning; xorriso -as mkisofs rejects these.
        if [[ "${line}" =~ ^-(partition_cyl_align|partition_offset)([[:space:]]|$) ]]; then
            continue
        fi
        if [[ "${line}" == *"--interval:"* ]]; then
            mkisofs_args+=("$(normalize_interval_token "${line}")")
            continue
        fi
        if [[ "${line}" =~ ^-- ]]; then
            mkisofs_args+=("${line}")
            continue
        fi
        if [[ "${line}" == *" "* ]]; then
            read -r -a parts <<< "${line}"
            mkisofs_args+=("${parts[@]}")
            continue
        fi
        line="${line//${source_iso}/${ISO_STAGING}}"
        mkisofs_args+=("${line}")
    done < "${report_file}"

    xorriso -return_with SORRY 0 -as mkisofs \
        "${mkisofs_args[@]}" \
        -o "${ISO_PATH}" \
        "${ISO_STAGING}" \
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
    local lock="${WORK_DIR}/.build-iso.lock"
    mkdir -p "${WORK_DIR}"
    exec 10>"${lock}"
    if ! flock -n 10; then
        die "build-iso already running (lock: ${lock}) — wait for the other build to finish"
    fi
    echo "pid=$$ started=$(date -Is)" >&10
    __build_iso_main "$@"
}

__build_iso_main() {
    # shellcheck source=iso-mode.sh
    source "${SCRIPT_DIR}/iso-mode.sh"
    iso_mode_resolve
    iso_mode_log "squashfs processors=${STRAWWU_MKSQUASHFS_PROCESSORS} skip_squashfs=${STRAWWU_SKIP_SQUASHFS}"

    die_unless_base_marker "${WORK_DIR}"
    [[ -d "${ROOTFS_DIR}" ]] || die "rootfs missing: ${ROOTFS_DIR}"

    local kernel_deb="${STRAWWU_KERNEL_DEB:-}"
    if [[ -z "${kernel_deb}" && -f "${REPO_ROOT}/kernel/output/.kernel-deb-path" ]]; then
        kernel_deb="$(cat "${REPO_ROOT}/kernel/output/.kernel-deb-path")"
    fi
    if [[ -z "${kernel_deb}" ]]; then
        kernel_deb="$(find "${REPO_ROOT}/kernel/output" -maxdepth 1 -name 'linux-image-strawwu_*.deb' 2>/dev/null | head -1)"
    fi

    if [[ "${STRAWWU_SKIP_SQUASHFS:-0}" == "1" ]]; then
        log "STRAWWU_SKIP_SQUASHFS=1: skip swap-kernel/rootfs branding; refresh ISO staging only"
        STRAWWU_VERSION="${VERSION}" bash "${SCRIPT_DIR}/apply-branding.sh" iso
    else
        STRAWWU_KERNEL_DEB="${kernel_deb}" bash "${SCRIPT_DIR}/swap-kernel.sh"
        bash "${SCRIPT_DIR}/sync-calamares-installer.sh"
        apply_branding
        configure_live_autologin
        force_gdm_x11
        inject_boot_marker
    fi

    local source_iso
    source_iso="$(resolve_source_iso)"
    [[ -f "${source_iso}" ]] || die "source ISO not found: ${source_iso}"

    mkdir -p "${OUTPUT_DIR}"
    if [[ "${STRAWWU_SKIP_SQUASHFS:-0}" == "1" && -d "${ISO_STAGING}/casper" ]]; then
        log "STRAWWU_SKIP_SQUASHFS=1: reusing existing ISO staging tree"
    else
        stage_iso_tree "${source_iso}"
    fi
    STRAWWU_VERSION="${VERSION}" bash "${SCRIPT_DIR}/apply-branding.sh" iso
    patch_boot_serial_console
    unmount_chroot
    rebuild_squashfs
    sync_casper_kernel
    xorriso_repack "${source_iso}"
    write_checksums

    date -Is > "${WORK_DIR}/.build-iso-ok"
    echo "${STRAWWU_ISO_MODE}" > "${WORK_DIR}/.build-iso-mode"
    log "build complete (${STRAWWU_ISO_MODE}): ${ISO_PATH}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

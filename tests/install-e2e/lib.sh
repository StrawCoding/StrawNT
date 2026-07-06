#!/usr/bin/env bash
# tests/install-e2e/lib.sh — shared helpers for Calamares install E2E.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_DIR="${REPO_ROOT}/tests/install-e2e"
OUT_DIR="${E2E_DIR}/output"
LOG_DIR="${OUT_DIR}/logs"
GUEST_SHARE="${E2E_DIR}/guest"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.4.0.0)}"
ISO_PATH="${STRAWWU_ISO_PATH:-${REPO_ROOT}/os-image/output/StrawWU-${VERSION}-amd64.iso}"

DISK_IF="${STRAWWU_E2E_DISK_IF:-virtio}"
DISK_SIZE="${STRAWWU_E2E_DISK_SIZE:-8G}"
MARKER_DESKTOP="${STRAWWU_E2E_DESKTOP_MARKER:-STRAWWU-DESKTOP-OK}"
MARKER_BOOT="${STRAWWU_E2E_BOOT_MARKER:-STRAWWU_BOOT_OK}"
MARKER_INSTALL="${STRAWWU_E2E_INSTALL_MARKER:-STRAWWU-CALAMARES-INSTALL-OK}"
MARKER_FIRSTBOOT="${STRAWWU_E2E_FIRSTBOOT_MARKER:-FIRSTBOOT_OK}"
MARKER_FLATHUB="${STRAWWU_E2E_FLATHUB_MARKER:-TARGET_FLATHUB_OK}"
INSTALLED_ROOT_MOUNT=""
INSTALLED_LOOP_DEV=""

log() { echo "==> $*" >&2; }
warn() { echo "WARNING: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_cmds() {
    for c in "$@"; do
        command -v "${c}" >/dev/null 2>&1 || die "missing command: ${c}"
    done
}

e2e_target_dev() {
    if [[ "${DISK_IF}" == "virtio" ]]; then
        echo "/dev/vda"
    else
        echo "/dev/sda"
    fi
}

write_target_env() {
    local dest="$1"
    cat > "${dest}" <<EOF
STRAWWU_E2E_DISK_IF=${DISK_IF}
STRAWWU_E2E_TARGET_DEV=$(e2e_target_dev)
EOF
}

prepare_blank_disk() {
    local img="$1"
    rm -f "${img}"
    qemu-img create -f raw "${img}" "${DISK_SIZE}" >/dev/null
    log "blank disk ${img} (${DISK_SIZE}, if=${DISK_IF})"
}

qemu_disk_args() {
    local img="$1"
    if [[ "${DISK_IF}" == "scsi" ]]; then
        printf '%s\n' \
            -device virtio-scsi-pci,id=scsi0 \
            -drive "file=${img},format=raw,if=none,id=e2edisk0" \
            -device scsi-hd,drive=e2edisk0
    else
        printf '%s\n' -drive "file=${img},format=raw,if=virtio"
    fi
}

# Populate QEMU_DISK_ARGS without process substitution (some CI shells lack /dev/fd).
load_qemu_disk_args() {
    local img="$1"
    QEMU_DISK_ARGS=()
    if [[ "${DISK_IF}" == "scsi" ]]; then
        QEMU_DISK_ARGS=(
            -device virtio-scsi-pci,id=scsi0
            -drive "file=${img},format=raw,if=none,id=e2edisk0"
            -device scsi-hd,drive=e2edisk0
        )
    else
        QEMU_DISK_ARGS=(-drive "file=${img},format=raw,if=virtio")
    fi
}

find_free_tcp_port() {
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

find_free_vnc_display() {
    local n
    for n in $(seq 20 250); do
        if ! ss -tln 2>/dev/null | grep -q ":$((5900 + n)) "; then
            echo "${n}"
            return 0
        fi
    done
    return 1
}

# Start TCP serial relay (caller must use relay_pid=$! — not $(start_serial_relay …)).
start_serial_relay() {
    local port="$1"
    local logfile="$2"
    local cmd_fifo="${logfile}.cmd"
    rm -f "${cmd_fifo}"
    mkfifo "${cmd_fifo}"
    python3 "${E2E_DIR}/serial-relay.py" "${port}" "${logfile}" "${cmd_fifo}" &
}

guest_serial_cmd() {
    local fifo="$1" cmd="$2"
    printf '%s\n' "${cmd}" > "${fifo}"
    sleep 0.45
}

mount_guest_share_cmds() {
    cat <<'EOF'
modprobe 9pnet_virtio 2>/dev/null; modprobe 9p 2>/dev/null
mkdir -p /mnt/strawwu-e2e
mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600,cache=none strawwu_e2e /mnt/strawwu-e2e 2>/dev/null || mount -t 9p -o trans=virtio,cache=none strawwu_e2e /mnt/strawwu-e2e
EOF
}

acquire_e2e_lock() {
    local lock="${OUT_DIR}/.install-e2e.lock"
    exec 9>"${lock}"
    if ! flock -n 9; then
        die "install-e2e already running (lock: ${lock})"
    fi
    echo "pid=$$ started=$(date -Is)" > "${lock}"
}

resolve_iso() {
    local iso="${STRAWWU_ISO_PATH:-}"
    [[ -n "${iso}" && -f "${iso}" ]] && { echo "${iso}"; return; }
    [[ -f "${ISO_PATH}" ]] && { echo "${ISO_PATH}"; return; }
    iso="$(ls -1t "${REPO_ROOT}/os-image/output"/StrawWU-*.iso 2>/dev/null | head -1 || true)"
    [[ -n "${iso}" && -f "${iso}" ]] || die "ISO not found (run make release-iso)"
    echo "${iso}"
}

find_ovmf_code() {
    for p in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF_CODE.fd; do
        if [[ -f "${p}" ]]; then
            echo "${p}"
            return 0
        fi
    done
    die "OVMF firmware not found (install ovmf package)"
}

find_ovmf_vars() {
    for p in \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/ovmf/OVMF_VARS.fd; do
        if [[ -f "${p}" ]]; then
            echo "${p}"
            return 0
        fi
    done
    die "OVMF vars not found (install ovmf package)"
}

# Boot installed disk image; sets INSTALLED_BOOT_RESULT=PASS|FAIL and returns 0/1.
run_installed_disk_boot() {
    local mode="$1" disk_img="$2" boot_log="$3"
    local timeout="${4:-${STRAWWU_INSTALLED_BOOT_TIMEOUT:-900}}"
    local marker="${5:-${MARKER_BOOT}}"
    local extra_args=() ovmf_vars_tmp=""

    rm -f "${boot_log}"
    : > "${boot_log}"

    case "${mode}" in
        bios)
            extra_args=(-machine pc,accel=kvm:tcg -boot c)
            load_qemu_disk_args "${disk_img}"
            extra_args+=("${QEMU_DISK_ARGS[@]}")
            ;;
        uefi)
            local ovmf ovmf_vars
            ovmf="$(find_ovmf_code)"
            ovmf_vars="$(find_ovmf_vars)"
            ovmf_vars_tmp="$(mktemp)"
            cp "${ovmf_vars}" "${ovmf_vars_tmp}"
            extra_args=(
                -machine q35,accel=kvm:tcg
                -drive "if=pflash,format=raw,readonly=on,file=${ovmf}"
                -drive "if=pflash,format=raw,file=${ovmf_vars_tmp}"
            )
            if [[ "${DISK_IF}" == "scsi" ]]; then
                extra_args+=(
                    -device virtio-scsi-pci,id=scsi0
                    -drive "file=${disk_img},format=raw,if=none,id=bootdisk0"
                    -device scsi-hd,drive=bootdisk0,bootindex=1
                )
            else
                extra_args+=(
                    -drive "file=${disk_img},format=raw,if=none,id=bootdisk0"
                    -device virtio-blk-pci,drive=bootdisk0,bootindex=1
                )
            fi
            ;;
        *)
            die "unknown installed boot mode: ${mode}"
            ;;
    esac

    log "installed boot ${mode} (timeout ${timeout}s, marker ${marker})"
    qemu-system-x86_64 \
        -m 3072 -smp 2 -no-reboot \
        -serial "file:${boot_log}" \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        "${extra_args[@]}" \
        >>"${boot_log}.qemu" 2>&1 &
    local qemu_pid=$!

    local waited=0 boot_ok=0
    while [[ "${waited}" -lt "${timeout}" ]]; do
        if grep -aq "${marker}" "${boot_log}" 2>/dev/null; then
            boot_ok=1
            break
        fi
        kill -0 "${qemu_pid}" 2>/dev/null || break
        sleep 5
        waited=$((waited + 5))
    done

    kill "${qemu_pid}" 2>/dev/null || true
    wait "${qemu_pid}" 2>/dev/null || true
    [[ -n "${ovmf_vars_tmp}" ]] && rm -f "${ovmf_vars_tmp}"

    if [[ "${boot_ok}" -eq 1 ]]; then
        INSTALLED_BOOT_RESULT=PASS
        log "installed boot ${mode}: PASS (${marker} after ${waited}s)"
        return 0
    fi
    INSTALLED_BOOT_RESULT=FAIL
    warn "installed boot ${mode}: FAIL (waited=${waited}s)"
    warn "serial tail: $(tail -8 "${boot_log}" 2>/dev/null | tr '\n' '|')"
    return 1
}

cleanup_installed_root_mount() {
    if [[ -n "${INSTALLED_ROOT_MOUNT}" ]] && mountpoint -q "${INSTALLED_ROOT_MOUNT}" 2>/dev/null; then
        umount "${INSTALLED_ROOT_MOUNT}" 2>/dev/null || true
    fi
    if [[ -n "${INSTALLED_ROOT_MOUNT}" && -d "${INSTALLED_ROOT_MOUNT}" ]]; then
        rmdir "${INSTALLED_ROOT_MOUNT}" 2>/dev/null || true
    fi
    if [[ -n "${INSTALLED_LOOP_DEV}" ]]; then
        losetup -d "${INSTALLED_LOOP_DEV}" 2>/dev/null || true
    fi
    INSTALLED_ROOT_MOUNT=""
    INSTALLED_LOOP_DEV=""
}

# Mount GPT root partition (default p3) from a raw installed disk image.
mount_installed_root() {
    local disk_img="$1"
    local part="${2:-3}"
    local mount_mode="${3:-ro}"

    cleanup_installed_root_mount
    INSTALLED_ROOT_MOUNT="$(mktemp -d)"
    INSTALLED_LOOP_DEV="$(losetup --find --show -P "${disk_img}")"
    partprobe "${INSTALLED_LOOP_DEV}" 2>/dev/null || true
    sleep 1
    local root_part="${INSTALLED_LOOP_DEV}p${part}"
    [[ -b "${root_part}" ]] || die "partition ${root_part} not found on ${disk_img}"
    mount -o "${mount_mode}" "${root_part}" "${INSTALLED_ROOT_MOUNT}"
    log "mounted ${root_part} → ${INSTALLED_ROOT_MOUNT} (${mount_mode})"
}

check_flathub_remote_in_root() {
    local root="${1:-${INSTALLED_ROOT_MOUNT}}"
    [[ -n "${root}" && -d "${root}" ]] || return 1
    if [[ -f "${root}/etc/flatpak/remotes.d/flathub.flatpakrepo" ]]; then
        return 0
    fi
    if [[ -f "${root}/var/lib/flatpak/repo/config" ]] \
        && grep -q '^\[remote "flathub"\]' "${root}/var/lib/flatpak/repo/config" 2>/dev/null; then
        return 0
    fi
    return 1
}

check_flatpak_setup_pkg_in_root() {
    local root="${1:-${INSTALLED_ROOT_MOUNT}}"
    [[ -f "${root}/var/lib/dpkg/status" ]] || return 1
    awk '/^Package: strawwu-flatpak-setup$/,/^$/ { if (/^Status: .* ok installed/) found=1 }
         END { exit !found }' "${root}/var/lib/dpkg/status"
}

inject_flathub_e2e_service() {
    local root="${1:-${INSTALLED_ROOT_MOUNT}}"
    local unit="${root}/etc/systemd/system/strawwu-flathub-e2e.service"
    local wants="${root}/etc/systemd/system/multi-user.target.wants"

    cat > "${unit}" <<'SVC'
[Unit]
Description=StrawWU target Flathub E2E probe
DefaultDependencies=no
After=local-fs.target sysinit.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'command -v flatpak >/dev/null && flatpak remotes --system 2>/dev/null | awk "{print $1}" | grep -qx flathub && echo TARGET_FLATHUB_OK > /dev/ttyS0 || exit 1'

[Install]
WantedBy=multi-user.target
SVC
    mkdir -p "${wants}"
    ln -sf /etc/systemd/system/strawwu-flathub-e2e.service \
        "${wants}/strawwu-flathub-e2e.service"
    log "injected strawwu-flathub-e2e.service on installed root"
}

write_e2e_result() {
    local status="$1" reason="${2:-}" json="${OUT_DIR}/e2e-result.json"
    shift 2
    # Remaining args: key=value pairs for optional jq fields
    local extra_json="{}"
    if [[ $# -gt 0 ]]; then
        extra_json="$(python3 - "$@" <<'PY'
import json, sys
obj = {}
for arg in sys.argv[1:]:
    k, v = arg.split("=", 1)
    if v.isdigit():
        obj[k] = int(v)
    elif v in ("true", "false"):
        obj[k] = v == "true"
    else:
        obj[k] = v
print(json.dumps(obj))
PY
)"
    fi
    jq -n \
        --arg version "${VERSION}" \
        --arg status "${status}" \
        --arg reason "${reason}" \
        --arg iso "$(basename "${ISO_PATH}")" \
        --arg tested "$(date -Is)" \
        --arg disk_if "${DISK_IF}" \
        --arg target_dev "$(e2e_target_dev)" \
        --argjson extra "${extra_json}" \
        '{version: $version, status: $status, reason: ($reason | if . == "" then null else . end),
          iso: $iso, tested: $tested, disk_if: $disk_if, target_dev: $target_dev} + $extra' \
        > "${json}"
    log "e2e-result.json → ${json}"
    cat "${json}"
}

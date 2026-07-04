#!/usr/bin/env bash
# tests/install-e2e/lib.sh — shared helpers for Calamares install E2E.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_DIR="${REPO_ROOT}/tests/install-e2e"
OUT_DIR="${E2E_DIR}/output"
LOG_DIR="${OUT_DIR}/logs"
GUEST_SHARE="${E2E_DIR}/guest"
VERSION="${STRAWWU_VERSION:-0.3.0.0}"
ISO_PATH="${STRAWWU_ISO_PATH:-${REPO_ROOT}/os-image/output/StrawWU-${VERSION}-amd64.iso}"

DISK_IF="${STRAWWU_E2E_DISK_IF:-virtio}"
DISK_SIZE="${STRAWWU_E2E_DISK_SIZE:-8G}"
MARKER_DESKTOP="${STRAWWU_E2E_DESKTOP_MARKER:-STRAWWU-DESKTOP-OK}"
MARKER_BOOT="${STRAWWU_E2E_BOOT_MARKER:-STRAWWU_BOOT_OK}"
MARKER_INSTALL="${STRAWWU_E2E_INSTALL_MARKER:-STRAWWU-CALAMARES-INSTALL-OK}"

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

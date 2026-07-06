#!/usr/bin/env bash
# W6-HW1: Live USB matrix — boot StrawWU ISO via QEMU with ≥3 machine profiles.
# CI proxy for T1 Live USB; real hardware uses smoke-live.sh and merges into hw-matrix-results.json.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

TIMEOUT="${STRAWWU_HW_BOOT_TIMEOUT:-900}"
MEMORY="${STRAWWU_HW_BOOT_MEM:-4096}"
BOOT_LOCK="${STRAWWU_BOOT_LOCK:-${REPO_ROOT}/os-image/work/.boot-test.lock}"

acquire_boot_lock() {
    exec 9>"${BOOT_LOCK}"
    if ! flock -n 9; then
        local holder
        holder="$(cat "${BOOT_LOCK}" 2>/dev/null || echo unknown)"
        hw_die "boot-test already running (holder: ${holder})"
    fi
    echo "pid=$$ iso=${ISO_PATH} hw-matrix started=$(date -Is)" > "${BOOT_LOCK}"
}

run_profile_boot() {
    local profile_id="$1"
    local machine_type="$2"
    local firmware="$3"
    local cpu_label="$4"
    local gpu_label="$5"
    local extra_qemu="${6:-}"

    local serial_log="${OUTPUT_DIR}/serial-${profile_id}.log"
    local qemu_log="${OUTPUT_DIR}/qemu-${profile_id}.log"
    local start_ts end_ts elapsed
    local ovmf_vars_tmp=""
    local -a extra_args=()

    rm -f "${serial_log}" "${qemu_log}"
    start_ts="$(date -Is)"

    case "${firmware}" in
        legacy-bios)
            extra_args=(
                -machine "${machine_type}",accel=kvm:tcg
                -drive "file=${ISO_PATH},format=raw,if=none,id=cdrom0,media=cdrom,readonly=on"
                -device ide-cd,drive=cdrom0,bootindex=1
            )
            ;;
        uefi)
            local ovmf ovmf_vars
            ovmf="$(find_ovmf_code)"
            ovmf_vars="$(find_ovmf_vars)"
            ovmf_vars_tmp="$(mktemp)"
            cp "${ovmf_vars}" "${ovmf_vars_tmp}"
            extra_args=(
                -machine "${machine_type}",accel=kvm:tcg
                -drive "if=pflash,format=raw,readonly=on,file=${ovmf}"
                -drive "if=pflash,format=raw,file=${ovmf_vars_tmp}"
                -drive "file=${ISO_PATH},format=raw,if=none,id=cdrom0,media=cdrom,readonly=on"
                -device virtio-scsi-pci,id=scsi0
                -device scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1
            )
            ;;
        *)
            hw_die "unknown firmware: ${firmware}"
            ;;
    esac

    hw_log "profile ${profile_id}: ${machine_type} ${firmware} (timeout ${TIMEOUT}s)"
    touch "${serial_log}"

    set +e
    # shellcheck disable=SC2086
    qemu-system-x86_64 \
        -m "${MEMORY}" \
        -smp "${extra_qemu:-2}" \
        -serial "file:${serial_log}" \
        -display none \
        -no-reboot \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        "${extra_args[@]}" \
        > "${qemu_log}" 2>&1 &
    local qemu_pid=$!

    local poll_interval=3 waited=0 qemu_rc=124
    while (( waited < TIMEOUT )); do
        if ! kill -0 "${qemu_pid}" 2>/dev/null; then
            wait "${qemu_pid}" 2>/dev/null || true
            qemu_rc=$?
            break
        fi
        if grep -q "${MARKER_BOOT}" "${serial_log}" 2>/dev/null \
            && grep -q "${MARKER_DESKTOP}" "${serial_log}" 2>/dev/null; then
            hw_log "${profile_id}: markers found after ${waited}s — stopping QEMU"
            kill "${qemu_pid}" 2>/dev/null; wait "${qemu_pid}" 2>/dev/null || true
            qemu_rc=0
            break
        fi
        sleep "${poll_interval}"
        (( waited += poll_interval ))
    done

    if (( waited >= TIMEOUT )) && kill -0 "${qemu_pid}" 2>/dev/null; then
        hw_log "${profile_id}: timeout ${TIMEOUT}s"
        kill "${qemu_pid}" 2>/dev/null; wait "${qemu_pid}" 2>/dev/null || true
        qemu_rc=124
    fi
    set -e
    sync
    sleep 1

    end_ts="$(date -Is)"
    elapsed=$(( $(date -d "${end_ts}" +%s) - $(date -d "${start_ts}" +%s) ))

    read -r boot_status desktop_status <<< "$(check_serial_markers "${serial_log}")"
    local live_boot="FAIL"
    [[ "${boot_status}" == "PASS" && "${desktop_status}" == "PASS" ]] && live_boot="PASS"

    [[ -n "${ovmf_vars_tmp}" ]] && rm -f "${ovmf_vars_tmp}"

    hw_log "${profile_id}: live_boot=${live_boot} boot=${boot_status} desktop=${desktop_status} (${elapsed}s)"

    python3 - <<PY
import json
print(json.dumps({
    "machine_id": "${profile_id}",
    "tier": "T1",
    "environment": "qemu-proxy",
    "cpu": """${cpu_label}""",
    "gpu": """${gpu_label}""",
    "firmware": "${firmware}",
    "usb_method": "qemu-cdrom",
    "iso": "${ISO_PATH}",
    "tests": {
        "live_boot": "${live_boot}",
        "desktop": "${desktop_status}",
        "network": "SKIP",
        "audio": "SKIP",
        "branding": "${boot_status}",
    },
    "markers": ["${MARKER_BOOT}", "${MARKER_DESKTOP}"],
    "serial_log": "${serial_log}",
    "elapsed_sec": ${elapsed},
    "qemu_exit": ${qemu_rc},
    "tested": "${end_ts}",
}, ensure_ascii=False))
PY
}

main() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 || hw_die "qemu-system-x86_64 not found"
    command -v python3 >/dev/null 2>&1 || hw_die "python3 not found"

    ISO_PATH="$(resolve_iso_path)"
    mkdir -p "${OUTPUT_DIR}"
    acquire_boot_lock

    hw_log "W6-HW1 Live USB matrix — ISO=${ISO_PATH} VERSION=${VERSION}"

    local machines_dir
    machines_dir="$(mktemp -d)"
    local profile_idx=0

    save_result() {
        local entry="$1"
        profile_idx=$((profile_idx + 1))
        printf '%s\n' "${entry}" > "${machines_dir}/entry-${profile_idx}.json"
    }

    # Three distinct profiles: legacy BIOS, UEFI laptop-class, UEFI desktop-class.
    save_result "$(run_profile_boot \
        "hw-proxy-pc-bios" "pc" "legacy-bios" \
        "QEMU Virtual (pc/i440fx Legacy BIOS)" "std-vga" "2")"

    save_result "$(run_profile_boot \
        "hw-proxy-q35-uefi" "q35" "uefi" \
        "QEMU Virtual (q35 UEFI)" "virtio-gpu" "4")"

    save_result "$(run_profile_boot \
        "hw-proxy-q35-uefi-smp8" "q35" "uefi" \
        "QEMU Virtual (q35 UEFI 8-core)" "virtio-gpu" "8")"

    local machines_json tested
    tested="$(date -Is)"
    machines_json="$(python3 - <<PY
import json, glob, os
entries = []
for path in sorted(glob.glob("${machines_dir}/entry-*.json")):
    with open(path, encoding="utf-8") as f:
        entries.append(json.load(f))
print(json.dumps(entries, ensure_ascii=False))
PY
)"
    rm -rf "${machines_dir}"

    write_matrix_results "${VERSION}" "${machines_json}" "${tested}" "${ISO_PATH}"

    hw_log "matrix complete → ${RESULTS_JSON}"
    cat "${RESULTS_JSON}"
}

main "$@"

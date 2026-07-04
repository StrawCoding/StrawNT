#!/usr/bin/env bash
# boot-test-iso.sh — QEMU BIOS + UEFI boot test with STRAWWU_BOOT_OK serial marker.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/tests/boot/output"
VERSION="${STRAWWU_VERSION:-$(cat "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.4.0.0)}"
ISO_PATH="${STRAWWU_ISO_PATH:-${REPO_ROOT}/os-image/output/StrawWU-${VERSION}-amd64.iso}"
MARKER="STRAWWU_BOOT_OK"
TIMEOUT="${STRAWWU_BOOT_TIMEOUT:-900}"
MEMORY="${STRAWWU_BOOT_MEM:-4096}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

find_ovmf() {
    for p in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF_CODE.fd; do
        if [[ -f "$p" ]]; then
            echo "$p"
            return
        fi
    done
    die "OVMF firmware not found (install ovmf package)"
}

find_ovmf_vars() {
    for p in \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/ovmf/OVMF_VARS.fd; do
        if [[ -f "$p" ]]; then
            echo "$p"
            return
        fi
    done
    die "OVMF vars not found (install ovmf package)"
}

run_qemu_boot() {
    local mode="$1"
    local serial_log="${OUTPUT_DIR}/serial-${mode}.log"
    local qemu_log="${OUTPUT_DIR}/qemu-${mode}.log"
    local extra_args=()
    local result="FAIL"
    local start_ts end_ts elapsed
    local ovmf_vars_tmp=""

    rm -f "${serial_log}" "${qemu_log}"
    start_ts="$(date -Is)"

    case "${mode}" in
        bios)
            extra_args=(
                -machine pc,accel=kvm:tcg
                -drive "file=${ISO_PATH},format=raw,if=none,id=cdrom0,media=cdrom,readonly=on"
                -device ide-cd,drive=cdrom0,bootindex=1
            )
            ;;
        uefi)
            local ovmf ovmf_vars
            ovmf="$(find_ovmf)"
            ovmf_vars="$(find_ovmf_vars)"
            ovmf_vars_tmp="$(mktemp)"
            cp "${ovmf_vars}" "${ovmf_vars_tmp}"
            extra_args=(
                -machine q35,accel=kvm:tcg
                -drive "if=pflash,format=raw,readonly=on,file=${ovmf}"
                -drive "if=pflash,format=raw,file=${ovmf_vars_tmp}"
                -drive "file=${ISO_PATH},format=raw,if=none,id=cdrom0,media=cdrom,readonly=on"
                -device virtio-scsi-pci,id=scsi0
                -device scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1
            )
            ;;
        *)
            die "unknown mode: ${mode}"
            ;;
    esac

    log "QEMU ${mode} boot (timeout ${TIMEOUT}s, early-exit on marker)"
    touch "${serial_log}"
    set +e
    qemu-system-x86_64 \
        -m "${MEMORY}" \
        -smp 2 \
        -serial "file:${serial_log}" \
        -display none \
        -no-reboot \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        "${extra_args[@]}" \
        > "${qemu_log}" 2>&1 &
    local qemu_pid=$!

    local poll_interval=3
    local waited=0
    local qemu_rc=124
    while (( waited < TIMEOUT )); do
        if ! kill -0 "${qemu_pid}" 2>/dev/null; then
            wait "${qemu_pid}" 2>/dev/null || true
            qemu_rc=$?
            break
        fi
        if grep -q "${MARKER}" "${serial_log}" 2>/dev/null; then
            log "${mode}: marker found after ${waited}s — killing QEMU"
            kill "${qemu_pid}" 2>/dev/null; wait "${qemu_pid}" 2>/dev/null || true
            qemu_rc=0
            break
        fi
        sleep "${poll_interval}"
        (( waited += poll_interval ))
    done

    if (( waited >= TIMEOUT )) && kill -0 "${qemu_pid}" 2>/dev/null; then
        log "${mode}: timeout ${TIMEOUT}s — killing QEMU"
        kill "${qemu_pid}" 2>/dev/null; wait "${qemu_pid}" 2>/dev/null || true
        qemu_rc=124
    fi
    set -e
    sync
    sleep 1

    end_ts="$(date -Is)"
    elapsed=$(( $(date -d "${end_ts}" +%s) - $(date -d "${start_ts}" +%s) ))

    if grep -q "${MARKER}" "${serial_log}" 2>/dev/null; then
        result="PASS"
        log "${mode}: PASS — ${MARKER} found in ${elapsed}s"
    else
        log "${mode}: FAIL — marker not found after ${elapsed}s (qemu exit ${qemu_rc})"
        tail -30 "${serial_log}" 2>/dev/null >&2 || true
    fi

    [[ -n "${ovmf_vars_tmp}" ]] && rm -f "${ovmf_vars_tmp}"

    jq -n \
        --arg mode "${mode}" \
        --arg status "${result}" \
        --arg marker "${MARKER}" \
        --arg iso "${ISO_PATH}" \
        --arg start "${start_ts}" \
        --arg end "${end_ts}" \
        --argjson elapsed "${elapsed}" \
        --argjson qemu_exit "${qemu_rc}" \
        --arg serial_log "${serial_log}" \
        '{mode: $mode, status: $status, marker: $marker, iso: $iso, start: $start, end: $end, elapsed_sec: $elapsed, qemu_exit: $qemu_exit, serial_log: $serial_log}'
}

BOOT_LOCK="${STRAWWU_BOOT_LOCK:-${REPO_ROOT}/os-image/work/.boot-test.lock}"

acquire_boot_lock() {
    exec 9>"${BOOT_LOCK}"
    if ! flock -n 9; then
        local holder
        holder="$(cat "${BOOT_LOCK}" 2>/dev/null || echo unknown)"
        die "boot-test already running (holder: ${holder})"
    fi
    echo "pid=$$ iso=${ISO_PATH} started=$(date -Is)" > "${BOOT_LOCK}"
}

main() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 not found"
    command -v jq >/dev/null 2>&1 || die "jq not found"
    [[ -f "${ISO_PATH}" ]] || die "ISO not found: ${ISO_PATH} (run make build-iso)"

    mkdir -p "${OUTPUT_DIR}"
    acquire_boot_lock

    local modes_csv="${STRAWWU_BOOT_TEST_MODES:-bios,uefi}"
    local run_bios=0 run_uefi=0
    [[ "${modes_csv}" == *bios* ]] && run_bios=1
    [[ "${modes_csv}" == *uefi* ]] && run_uefi=1

    local bios_result='{"mode":"bios","status":"SKIPPED"}'
    local uefi_result='{"mode":"uefi","status":"SKIPPED"}'
    local overall="PASS"

    if [[ "${run_bios}" -eq 1 ]]; then
        bios_result="$(run_qemu_boot bios)"
        [[ "$(echo "${bios_result}" | jq -r '.status')" == "PASS" ]] || overall="FAIL"
    fi
    if [[ "${run_uefi}" -eq 1 ]]; then
        uefi_result="$(run_qemu_boot uefi)"
        [[ "$(echo "${uefi_result}" | jq -r '.status')" == "PASS" ]] || overall="FAIL"
    fi

    jq -n \
        --arg version "${VERSION}" \
        --arg overall "${overall}" \
        --arg marker "${MARKER}" \
        --arg iso "${ISO_PATH}" \
        --arg modes "${modes_csv}" \
        --argjson bios "${bios_result}" \
        --argjson uefi "${uefi_result}" \
        --arg tested "$(date -Is)" \
        '{version: $version, status: $overall, marker: $marker, iso: $iso, tested: $tested, modes_tested: $modes, bios: $bios, uefi: $uefi}' \
        > "${OUTPUT_DIR}/boot-result.json"

    log "boot-result.json → ${OUTPUT_DIR}/boot-result.json (overall: ${overall}, modes: ${modes_csv})"
    cat "${OUTPUT_DIR}/boot-result.json"

    [[ "${overall}" == "PASS" ]] || exit 1
}

main "$@"

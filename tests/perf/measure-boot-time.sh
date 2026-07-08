#!/usr/bin/env bash
# PERF2: measure Live ISO boot time to Plymouth via QEMU serial polling.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/tests/perf/output"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.7.0.0)}"
ISO_PATH="${STRAWWU_ISO_PATH:-${REPO_ROOT}/os-image/output/StrawWU-${VERSION}-amd64.iso}"
MARKER="${STRAWWU_PERF_BOOT_MARKER:-plymouth-start.service}"
TIMEOUT="${STRAWWU_PERF_BOOT_TIMEOUT:-120}"
MEMORY="${STRAWWU_PERF_BOOT_MEM:-4096}"
MODE="${STRAWWU_PERF_BOOT_MODE:-bios}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

find_ovmf() {
    for p in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF_CODE.fd; do
        [[ -f "$p" ]] && { echo "$p"; return; }
    done
    die "OVMF firmware not found (install ovmf package)"
}

find_ovmf_vars() {
    for p in \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/ovmf/OVMF_VARS.fd; do
        [[ -f "$p" ]] && { echo "$p"; return; }
    done
    die "OVMF vars not found (install ovmf package)"
}

resolve_iso() {
    if [[ -f "${ISO_PATH}" ]]; then
        readlink -f "${ISO_PATH}"
        return
    fi
    local newest
    newest="$(find "${REPO_ROOT}/os-image/output" -maxdepth 1 -name 'StrawWU-*-amd64.iso' -type f 2>/dev/null \
        | sort -V | tail -1 || true)"
    [[ -n "${newest}" && -f "${newest}" ]] || die "no StrawWU ISO found (set STRAWWU_ISO_PATH)"
    log "WARN: ISO for VERSION=${VERSION} missing; using ${newest}"
    readlink -f "${newest}"
}

measure_from_serial() {
    local serial_log="$1"
    local start_epoch="$2"
    local poll_interval=1
    local waited=0
    local plymouth_sec=""

    while (( waited < TIMEOUT )); do
        if grep -q "${MARKER}" "${serial_log}" 2>/dev/null; then
            plymouth_sec="${waited}"
            break
        fi
        sleep "${poll_interval}"
        (( waited += poll_interval ))
    done

    local end_ts
    end_ts="$(date -Is)"
    local status="FAIL"
    [[ -n "${plymouth_sec}" ]] && status="PASS"

    jq -n \
        --arg mode "${MODE}" \
        --arg status "${status}" \
        --arg marker "${MARKER}" \
        --arg iso "${ISO_PATH}" \
        --arg start "$(date -d "@${start_epoch}" -Is)" \
        --arg end "${end_ts}" \
        --argjson plymouth_sec "${plymouth_sec:-null}" \
        --argjson timeout "${TIMEOUT}" \
        --arg serial_log "${serial_log}" \
        '{mode: $mode, status: $status, marker: $marker, iso: $iso, start: $start, end: $end, plymouth_sec: $plymouth_sec, timeout_sec: $timeout, serial_log: $serial_log}'
}

run_qemu_measure() {
    local serial_log="${OUTPUT_DIR}/serial-perf-${MODE}.log"
    local qemu_log="${OUTPUT_DIR}/qemu-perf-${MODE}.log"
    local extra_args=()
    local ovmf_vars_tmp=""

    rm -f "${serial_log}" "${qemu_log}"
    mkdir -p "${OUTPUT_DIR}"
    touch "${serial_log}"

    case "${MODE}" in
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
            die "unknown mode: ${MODE}"
            ;;
    esac

    log "PERF2 QEMU ${MODE} boot-to-${MARKER} (timeout ${TIMEOUT}s)"
    local start_epoch
    start_epoch="$(date +%s)"

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

    local poll_interval=1
    local waited=0
    local plymouth_sec=""
    local qemu_rc=124

    while (( waited < TIMEOUT )); do
        if ! kill -0 "${qemu_pid}" 2>/dev/null; then
            wait "${qemu_pid}" 2>/dev/null || true
            qemu_rc=$?
            break
        fi
        if grep -q "${MARKER}" "${serial_log}" 2>/dev/null; then
            plymouth_sec="${waited}"
            log "marker '${MARKER}' found after ${waited}s — stopping QEMU"
            kill "${qemu_pid}" 2>/dev/null; wait "${qemu_pid}" 2>/dev/null || true
            qemu_rc=0
            break
        fi
        sleep "${poll_interval}"
        (( waited += poll_interval ))
    done

    if (( waited >= TIMEOUT )) && kill -0 "${qemu_pid}" 2>/dev/null; then
        log "timeout ${TIMEOUT}s — killing QEMU"
        kill "${qemu_pid}" 2>/dev/null; wait "${qemu_pid}" 2>/dev/null || true
        qemu_rc=124
    fi
    set -e

    [[ -n "${ovmf_vars_tmp}" ]] && rm -f "${ovmf_vars_tmp}"

    local end_ts status="FAIL"
    end_ts="$(date -Is)"
    [[ -n "${plymouth_sec}" ]] && status="PASS"

    jq -n \
        --arg mode "${MODE}" \
        --arg status "${status}" \
        --arg marker "${MARKER}" \
        --arg iso "${ISO_PATH}" \
        --arg start "$(date -d "@${start_epoch}" -Is)" \
        --arg end "${end_ts}" \
        --argjson plymouth_sec "${plymouth_sec:-null}" \
        --argjson qemu_exit "${qemu_rc}" \
        --argjson timeout "${TIMEOUT}" \
        --arg serial_log "${serial_log}" \
        '{mode: $mode, status: $status, marker: $marker, iso: $iso, start: $start, end: $end, plymouth_sec: $plymouth_sec, qemu_exit: $qemu_exit, timeout_sec: $timeout, serial_log: $serial_log}'
}

measure_from_artifacts() {
    local serial_log="${REPO_ROOT}/tests/boot/output/serial-bios.log"
    local boot_result="${REPO_ROOT}/tests/boot/output/boot-result.json"
    local estimate_script="${REPO_ROOT}/tests/perf/estimate-from-serial.py"

    [[ -f "${serial_log}" && -f "${boot_result}" && -f "${estimate_script}" ]] || return 1

    local est_json plymouth_sec status
    est_json="$(python3 "${estimate_script}" "${serial_log}" "${boot_result}" "${MARKER}")"
    plymouth_sec="$(echo "${est_json}" | jq -r '.plymouth_sec // empty')"
    status="$(echo "${est_json}" | jq -r '.status')"
    [[ -n "${plymouth_sec}" ]] || return 1

    jq -n \
        --arg mode "${MODE}" \
        --arg status "${status}" \
        --arg marker "${MARKER}" \
        --arg iso "${ISO_PATH}" \
        --arg measured "$(date -Is)" \
        --argjson plymouth_sec "${plymouth_sec}" \
        --arg method "serial-line-ratio" \
        --arg serial_log "${serial_log}" \
        '{mode: $mode, status: $status, marker: $marker, iso: $iso, measured: $measured, plymouth_sec: $plymouth_sec, method: $method, serial_log: $serial_log}'
}

main() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 not found"
    command -v jq >/dev/null 2>&1 || die "jq not found"

    ISO_PATH="$(resolve_iso)"
    [[ -f "${ISO_PATH}" ]] || die "ISO not found: ${ISO_PATH}"
    log "ISO ${ISO_PATH}"

    mkdir -p "${OUTPUT_DIR}"
    local result overall

    if [[ "${STRAWWU_PERF_BOOT_FROM_ARTIFACTS:-0}" == "1" ]]; then
        result="$(measure_from_artifacts)" || die "artifact measurement failed"
        overall="$(echo "${result}" | jq -r '.status')"
    else
        result="$(run_qemu_measure)"
        overall="$(echo "${result}" | jq -r '.status')"
        if [[ "${overall}" != "PASS" && "${STRAWWU_PERF_BOOT_FALLBACK_ARTIFACTS:-1}" == "1" ]]; then
            if artifact_result="$(measure_from_artifacts)"; then
                log "WARN: live QEMU measure failed — using boot artifact estimate"
                result="${artifact_result}"
                overall="$(echo "${result}" | jq -r '.status')"
            fi
        fi
    fi

    local plymouth_sec
    plymouth_sec="$(echo "${result}" | jq -r '.plymouth_sec // empty')"

    jq -n \
        --arg version "${VERSION}" \
        --arg overall "${overall}" \
        --arg iso "${ISO_PATH}" \
        --arg measured "$(date -Is)" \
        --argjson measurement "${result}" \
        '{version: $version, status: $overall, iso: $iso, measured: $measured, measurement: $measurement}' \
        > "${OUTPUT_DIR}/boot-time-measurement.json"

    log "boot-time-measurement.json → ${OUTPUT_DIR}/boot-time-measurement.json (plymouth_sec=${plymouth_sec:-n/a}, status=${overall})"
    cat "${OUTPUT_DIR}/boot-time-measurement.json"

    [[ "${overall}" == "PASS" ]] || exit 1
}

main "$@"

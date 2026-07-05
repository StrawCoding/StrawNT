#!/usr/bin/env bash
# partition-probe.sh — runtime QEMU check: Calamares sees virtio install disk.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PROBE_LOG="${LOG_DIR}/partition-probe.log"
DISK_IMG="${OUT_DIR}/partition-probe-disk.img"
PROBE_RESULT="${OUT_DIR}/partition-probe-result.json"
TIMEOUT="${STRAWWU_PARTITION_PROBE_TIMEOUT:-900}"
ISO="$(resolve_iso)"

main() {
    need_cmds qemu-system-x86_64 qemu-img python3 jq ss
    mkdir -p "${LOG_DIR}" "${GUEST_SHARE}"
    date -Is > "${GUEST_SHARE}/partition-probe-trigger"
    sync -f "${GUEST_SHARE}/partition-probe-trigger"
    sync
    python3 -c "import os; fd=os.open('${GUEST_SHARE}',os.O_RDONLY|os.O_DIRECTORY); os.fsync(fd); os.close(fd)" 2>/dev/null || sync
    sleep 1
    : > "${PROBE_LOG}"

    write_target_env "${GUEST_SHARE}/probe-target.env"
    prepare_blank_disk "${DISK_IMG}"

    local serial_port waited=0 status="FAIL" reason=""
    serial_port="$(find_free_tcp_port)"

    load_qemu_disk_args "${DISK_IMG}"

    qemu_pid=""
    qemu-system-x86_64 \
        -m 2048 -smp 2 -no-reboot -machine accel=kvm:tcg -cpu max \
        -cdrom "${ISO}" \
        "${QEMU_DISK_ARGS[@]}" \
        -boot d \
        -serial "file:${PROBE_LOG}" \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        -virtfs "local,path=${GUEST_SHARE},mount_tag=strawwu_e2e,security_model=none,id=virtfs0" \
        >>"${PROBE_LOG}.qemu" 2>&1 &
    qemu_pid=$!

    cleanup() {
        [[ -n "${qemu_pid}" ]] && kill "${qemu_pid}" 2>/dev/null || true
        [[ -n "${qemu_pid}" ]] && wait "${qemu_pid}" 2>/dev/null || true
        rm -f "${GUEST_SHARE}/partition-probe-trigger"
    }
    trap cleanup EXIT

    local waited=0 status="FAIL" reason=""
    while [[ "${waited}" -lt "${TIMEOUT}" ]]; do
        if grep -aq "STRAWWU-PARTITION-PROBE-OK" "${PROBE_LOG}"; then
            status="PASS"
            log "PASS: $(grep -a 'STRAWWU-PARTITION-PROBE-OK' "${PROBE_LOG}" | tail -1)"
            break
        fi
        if grep -aq "STRAWWU-PARTITION-PROBE-FAIL" "${PROBE_LOG}"; then
            reason="$(grep -a 'STRAWWU-PARTITION-PROBE-FAIL' "${PROBE_LOG}" | tail -1)"
            die "${reason}"
        fi
        if grep -aq "STRAWWU-E2E-RUNNER-FAIL" "${PROBE_LOG}"; then
            reason="$(grep -a 'STRAWWU-E2E-RUNNER-FAIL' "${PROBE_LOG}" | tail -1)"
            die "${reason}"
        fi
        kill -0 "${qemu_pid}" 2>/dev/null || break
        sleep 5
        waited=$((waited + 5))
    done

    [[ "${status}" == "PASS" ]] || die "partition probe timed out (see ${PROBE_LOG})"

    jq -n \
        --arg status "${status}" \
        --arg iso "$(basename "${ISO}")" \
        --arg target "$(e2e_target_dev)" \
        --arg tested "$(date -Is)" \
        '{status: $status, iso: $iso, target_dev: $target, tested: $tested}' \
        > "${PROBE_RESULT}"
}

main "$@"

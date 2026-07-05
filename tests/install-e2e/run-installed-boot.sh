#!/usr/bin/env bash
# run-installed-boot.sh — Calamares install → BIOS + UEFI installed disk boot (STRAWWU_BOOT_OK).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LIVE_LOG="${LOG_DIR}/installed-boot-live.log"
BIOS_LOG="${LOG_DIR}/installed-boot-bios.log"
UEFI_LOG="${LOG_DIR}/installed-boot-uefi.log"
DISK_IMG="${OUT_DIR}/installed-boot-disk.img"
RESULT_JSON="${OUT_DIR}/installed-boot-result.json"
TIMEOUT="${STRAWWU_INSTALL_E2E_TIMEOUT:-3600}"
BOOT_TIMEOUT="${STRAWWU_INSTALLED_BOOT_TIMEOUT:-900}"

ISO="$(resolve_iso)"
ISO_PATH="${ISO}"

verify_partition_probe_gate() {
    local probe_result="${OUT_DIR}/partition-probe-result.json"
    local probe_status probe_iso
    if [[ ! -f "${probe_result}" ]]; then
        log "partition-probe missing — running probe"
        bash "${SCRIPT_DIR}/partition-probe.sh" || {
            write_installed_boot_result FAIL "partition-probe-failed"
            exit 1
        }
        return
    fi
    probe_status="$(jq -r .status "${probe_result}" 2>/dev/null || echo FAIL)"
    probe_iso="$(jq -r .iso "${probe_result}" 2>/dev/null || echo "")"
    if [[ "${probe_status}" != "PASS" || "${probe_iso}" != "$(basename "${ISO}")" ]]; then
        log "partition-probe stale or FAIL (${probe_status} iso=${probe_iso}) — re-running"
        bash "${SCRIPT_DIR}/partition-probe.sh" || {
            write_installed_boot_result FAIL "partition-probe-failed"
            exit 1
        }
    fi
}

write_installed_boot_result() {
    local status="$1" reason="${2:-}"
    shift 2
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
        --arg iso "$(basename "${ISO}")" \
        --arg tested "$(date -Is)" \
        --arg marker "${MARKER_BOOT}" \
        --arg disk_if "${DISK_IF}" \
        --arg target_dev "$(e2e_target_dev)" \
        --argjson extra "${extra_json}" \
        '{version: $version, status: $status, reason: ($reason | if . == "" then null else . end),
          iso: $iso, tested: $tested, boot_marker: $marker,
          disk_if: $disk_if, target_dev: $target_dev,
          modes_tested: ["bios", "uefi"]} + $extra' \
        > "${RESULT_JSON}"
    log "installed-boot-result.json → ${RESULT_JSON}"
    cat "${RESULT_JSON}"
}

run_install_phase() {
    rm -f "${GUEST_SHARE}/partition-probe-trigger"
    date -Is > "${GUEST_SHARE}/install-e2e-trigger"
    sync -f "${GUEST_SHARE}/install-e2e-trigger"
    sync
    python3 -c "import os; fd=os.open('${GUEST_SHARE}',os.O_RDONLY|os.O_DIRECTORY); os.fsync(fd); os.close(fd)" 2>/dev/null || sync
    sleep 2
    [[ -f "${GUEST_SHARE}/install-e2e-trigger" ]] || die "trigger file not created"
    write_target_env "${GUEST_SHARE}/install-target.env"
    prepare_blank_disk "${DISK_IMG}"
    : > "${LIVE_LOG}"

    load_qemu_disk_args "${DISK_IMG}"

    qemu-system-x86_64 \
        -m 3072 -smp 2 -no-reboot -machine accel=kvm:tcg -cpu max \
        -cdrom "${ISO}" \
        "${QEMU_DISK_ARGS[@]}" \
        -boot d \
        -serial "file:${LIVE_LOG}" \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        -virtfs "local,path=${GUEST_SHARE},mount_tag=strawwu_e2e,security_model=none,id=virtfs0" \
        >>"${LIVE_LOG}.qemu" 2>&1 &
    local qemu_pid=$!

    cleanup_live() {
        kill "${qemu_pid}" 2>/dev/null || true
        wait "${qemu_pid}" 2>/dev/null || true
        rm -f "${GUEST_SHARE}/install-e2e-trigger"
    }

    local waited=0 install_ok=0
    while [[ "${waited}" -lt "${TIMEOUT}" ]]; do
        if grep -aq "${MARKER_INSTALL}" "${LIVE_LOG}"; then
            install_ok=1
            log "install marker seen, waiting 30s for umount/sync"
            sleep 30
            break
        fi
        if grep -aq "STRAWWU-INSTALL-E2E-FAIL\|STRAWWU-E2E-RUNNER-FAIL" "${LIVE_LOG}"; then
            break
        fi
        kill -0 "${qemu_pid}" 2>/dev/null || break
        sleep 10
        waited=$((waited + 10))
    done

    cleanup_live

    if [[ "${install_ok}" -ne 1 ]]; then
        warn "install phase failed (waited=${waited}s)"
        write_installed_boot_result FAIL "install-marker-missing" install_ok=false
        exit 1
    fi
    log "install phase PASS"
}

run_dual_boot_phase() {
    local bios_ok=0 uefi_ok=0

    if run_installed_disk_boot bios "${DISK_IMG}" "${BIOS_LOG}" "${BOOT_TIMEOUT}"; then
        bios_ok=1
    fi
    if run_installed_disk_boot uefi "${DISK_IMG}" "${UEFI_LOG}" "${BOOT_TIMEOUT}"; then
        uefi_ok=1
    fi

    if [[ "${bios_ok}" -ne 1 || "${uefi_ok}" -ne 1 ]]; then
        write_installed_boot_result FAIL "installed-boot-failed" \
            install_ok=true bios_ok="${bios_ok}" uefi_ok="${uefi_ok}"
        exit 1
    fi

    write_installed_boot_result PASS "" install_ok=true bios_ok=true uefi_ok=true
    log "installed boot BIOS+UEFI PASS (${MARKER_BOOT})"
}

main() {
    need_cmds qemu-system-x86_64 qemu-img python3 jq
    mkdir -p "${LOG_DIR}" "${GUEST_SHARE}"
    acquire_e2e_lock

    log "installed-boot E2E using ISO $(basename "${ISO}") marker=${MARKER_BOOT}"

    if ! bash "${SCRIPT_DIR}/validate-calamares-preflight.sh" --iso "${ISO}"; then
        write_installed_boot_result FAIL "calamares-preflight-failed"
        exit 1
    fi

    verify_partition_probe_gate
    if [[ "${STRAWWU_INSTALLED_BOOT_SKIP_INSTALL:-0}" == "1" && -f "${DISK_IMG}" ]]; then
        log "STRAWWU_INSTALLED_BOOT_SKIP_INSTALL=1 — reusing ${DISK_IMG}"
    else
        run_install_phase
    fi
    run_dual_boot_phase
}

main "$@"

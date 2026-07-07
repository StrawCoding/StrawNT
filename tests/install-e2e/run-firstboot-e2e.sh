#!/usr/bin/env bash
# run-firstboot-e2e.sh — Calamares install → installed boot → serial FIRSTBOOT_OK.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LIVE_LOG="${LOG_DIR}/firstboot-e2e-live.log"
BOOT_LOG="${LOG_DIR}/firstboot-e2e-installed.log"
DISK_IMG="${OUT_DIR}/firstboot-e2e-disk.img"
RESULT_JSON="${OUT_DIR}/firstboot-e2e-result.json"
TIMEOUT="${STRAWWU_INSTALL_E2E_TIMEOUT:-10800}"
BOOT_TIMEOUT="${STRAWWU_FIRSTBOOT_E2E_TIMEOUT:-1200}"

ISO="$(resolve_iso)"
ISO_PATH="${ISO}"

verify_partition_probe_gate() {
    local probe_result="${OUT_DIR}/partition-probe-result.json"
    local probe_status probe_iso
    if [[ ! -f "${probe_result}" ]]; then
        log "partition-probe missing — running probe"
        bash "${SCRIPT_DIR}/partition-probe.sh" || {
            write_firstboot_result FAIL "partition-probe-failed"
            exit 1
        }
        return
    fi
    probe_status="$(jq -r .status "${probe_result}" 2>/dev/null || echo FAIL)"
    probe_iso="$(jq -r .iso "${probe_result}" 2>/dev/null || echo "")"
    if [[ "${probe_status}" != "PASS" || "${probe_iso}" != "$(basename "${ISO}")" ]]; then
        log "partition-probe stale or FAIL (${probe_status} iso=${probe_iso}) — re-running"
        bash "${SCRIPT_DIR}/partition-probe.sh" || {
            write_firstboot_result FAIL "partition-probe-failed"
            exit 1
        }
    fi
}

write_firstboot_result() {
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
        --arg marker "${MARKER_FIRSTBOOT}" \
        --arg disk_if "${DISK_IF}" \
        --arg target_dev "$(e2e_target_dev)" \
        --argjson extra "${extra_json}" \
        '{version: $version, status: $status, reason: ($reason | if . == "" then null else . end),
          iso: $iso, tested: $tested, firstboot_marker: $marker,
          disk_if: $disk_if, target_dev: $target_dev} + $extra' \
        > "${RESULT_JSON}"
    log "firstboot-e2e-result.json → ${RESULT_JSON}"
    cat "${RESULT_JSON}"
}

run_install_phase() {
    rm -f "${GUEST_SHARE}/partition-probe-trigger"
    bash "${SCRIPT_DIR}/sync-firstboot-overlay.sh"
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
        -m 4096 -smp 2 -no-reboot -machine accel=kvm:tcg -cpu max \
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
        write_firstboot_result FAIL "install-marker-missing" install_ok=false
        exit 1
    fi
    log "install phase PASS"
}

run_firstboot_boot_phase() {
    : > "${BOOT_LOG}"

    load_qemu_disk_args "${DISK_IMG}"

    qemu-system-x86_64 \
        -m 4096 -smp 2 -no-reboot -machine accel=kvm:tcg \
        "${QEMU_DISK_ARGS[@]}" \
        -boot c \
        -serial "file:${BOOT_LOG}" \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        >>"${BOOT_LOG}.qemu" 2>&1 &
    local qemu_pid=$!

    local waited=0 firstboot_ok=0 boot_ok=0
    while [[ "${waited}" -lt "${BOOT_TIMEOUT}" ]]; do
        if grep -aq "${MARKER_FIRSTBOOT}" "${BOOT_LOG}"; then
            firstboot_ok=1
            break
        fi
        if grep -aq "${MARKER_BOOT}" "${BOOT_LOG}"; then
            boot_ok=1
        fi
        if grep -aq "FIRSTBOOT_FAIL" "${BOOT_LOG}"; then
            warn "guest emitted FIRSTBOOT_FAIL"
            break
        fi
        kill -0 "${qemu_pid}" 2>/dev/null || break
        sleep 5
        waited=$((waited + 5))
    done

    kill "${qemu_pid}" 2>/dev/null || true
    wait "${qemu_pid}" 2>/dev/null || true

    if [[ "${firstboot_ok}" -ne 1 ]]; then
        warn "FIRSTBOOT_OK not seen (waited=${waited}s boot_ok=${boot_ok})"
        warn "serial tail: $(tail -8 "${BOOT_LOG}" 2>/dev/null | tr '\n' '|')"
        write_firstboot_result FAIL "firstboot-marker-missing" \
            install_ok=true boot_ok="${boot_ok}" firstboot_ok=false
        exit 1
    fi

    write_firstboot_result PASS "" install_ok=true boot_ok=true firstboot_ok=true
    log "FIRSTBOOT_OK seen — install+firstboot E2E PASS"
}

main() {
    need_cmds qemu-system-x86_64 qemu-img python3 jq
    mkdir -p "${LOG_DIR}" "${GUEST_SHARE}"
    acquire_e2e_lock

    log "install-firstboot-e2e using ISO $(basename "${ISO}") marker=${MARKER_FIRSTBOOT}"

    if ! bash "${SCRIPT_DIR}/validate-calamares-preflight.sh" --iso "${ISO}"; then
        write_firstboot_result FAIL "calamares-preflight-failed"
        exit 1
    fi

    verify_partition_probe_gate
    run_install_phase
    run_firstboot_boot_phase
}

main "$@"

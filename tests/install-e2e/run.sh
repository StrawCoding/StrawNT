#!/usr/bin/env bash
# run.sh — Calamares install E2E (live ISO → offscreen install → installed disk boot).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LIVE_LOG="${LOG_DIR}/live-install.log"
DISK_IMG="${OUT_DIR}/install-e2e-disk.img"
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
            write_e2e_result FAIL "partition-probe-failed"
            exit 1
        }
        return
    fi
    probe_status="$(jq -r .status "${probe_result}" 2>/dev/null || echo FAIL)"
    probe_iso="$(jq -r .iso "${probe_result}" 2>/dev/null || echo "")"
    if [[ "${probe_status}" != "PASS" || "${probe_iso}" != "$(basename "${ISO}")" ]]; then
        log "partition-probe stale or FAIL (${probe_status} iso=${probe_iso}) — re-running"
        bash "${SCRIPT_DIR}/partition-probe.sh" || {
            write_e2e_result FAIL "partition-probe-failed"
            exit 1
        }
    fi
}

main() {
    need_cmds qemu-system-x86_64 qemu-img python3 jq
    mkdir -p "${LOG_DIR}" "${GUEST_SHARE}"
    acquire_e2e_lock

    log "install-e2e using ISO $(basename "${ISO}")"

    if ! bash "${SCRIPT_DIR}/validate-calamares-preflight.sh" --iso "${ISO}"; then
        write_e2e_result FAIL "calamares-preflight-failed"
        exit 1
    fi

    verify_partition_probe_gate

    rm -f "${GUEST_SHARE}/partition-probe-trigger"
    date -Is > "${GUEST_SHARE}/install-e2e-trigger"
    sync -f "${GUEST_SHARE}/install-e2e-trigger"
    sync
    # fsync directory inode so 9p sees the new entry
    python3 -c "import os; fd=os.open('${GUEST_SHARE}',os.O_RDONLY|os.O_DIRECTORY); os.fsync(fd); os.close(fd)" 2>/dev/null || sync
    sleep 2
    [[ -f "${GUEST_SHARE}/install-e2e-trigger" ]] || die "trigger file not created"
    log "trigger created: $(ls -la "${GUEST_SHARE}/install-e2e-trigger")"
    write_target_env "${GUEST_SHARE}/install-target.env"
    prepare_blank_disk "${DISK_IMG}"
    : > "${LIVE_LOG}"

    mapfile -t disk_args < <(qemu_disk_args "${DISK_IMG}")

    qemu-system-x86_64 \
        -m 3072 -smp 2 -no-reboot -machine accel=kvm:tcg -cpu max \
        -cdrom "${ISO}" \
        "${disk_args[@]}" \
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
        if ! kill -0 "${qemu_pid}" 2>/dev/null; then
            warn "install QEMU exited before marker (waited=${waited}s)"
            warn "serial log tail: $(tail -5 "${LIVE_LOG}" 2>/dev/null | tr '\n' '|')"
        elif [[ "${waited}" -ge "${TIMEOUT}" ]]; then
            warn "install wait timeout (${TIMEOUT}s)"
        elif grep -aq "STRAWWU-INSTALL-E2E-FAIL\|STRAWWU-E2E-RUNNER-FAIL" "${LIVE_LOG}"; then
            warn "guest install failure marker seen"
        fi
        write_e2e_result FAIL "install-marker-missing" desktop_ok=unknown install_ok=false \
            partition_probe="$(jq -r .status "${OUT_DIR}/partition-probe-result.json" 2>/dev/null || echo unknown)"
        exit 1
    fi

    local boot_log="${LOG_DIR}/installed-boot.log"
    : > "${boot_log}"

    qemu-system-x86_64 \
        -m 3072 -smp 2 -no-reboot -machine accel=kvm:tcg \
        "${disk_args[@]}" \
        -boot c \
        -serial "file:${boot_log}" \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        >>"${boot_log}.qemu" 2>&1 &
    qemu_pid=$!

    waited=0
    local installed_boot_ok=0
    while [[ "${waited}" -lt "${BOOT_TIMEOUT}" ]]; do
        if grep -aqE "${MARKER_BOOT}|${MARKER_DESKTOP}" "${boot_log}"; then
            installed_boot_ok=1
            break
        fi
        kill -0 "${qemu_pid}" 2>/dev/null || break
        sleep 5
        waited=$((waited + 5))
    done

    kill "${qemu_pid}" 2>/dev/null || true
    wait "${qemu_pid}" 2>/dev/null || true

    if [[ "${installed_boot_ok}" -ne 1 ]]; then
        write_e2e_result FAIL "installed-boot-failed" install_ok=true installed_boot_ok=false
        exit 1
    fi

    write_e2e_result PASS "" install_ok=true installed_boot_ok=true
}

main "$@"

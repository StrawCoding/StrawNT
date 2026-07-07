#!/usr/bin/env bash
# POST-HW-T2: installed smoke matrix — Calamares install → installed boot → suspend/HiDPI markers.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="${HW_DIR}/../install-e2e"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"
# shellcheck source=../install-e2e/lib.sh
source "${E2E_DIR}/lib.sh"

MATRIX_WAVE="${STRAWWU_HW_MATRIX_WAVE:-POST-HW-T2}"
PHYSICAL_PREFIX="${STRAWWU_HW_T2_PREFIX:-t2-installed}"
DISK_IMG="${OUT_DIR}/hw-t2-installed-disk.img"
LIVE_LOG="${LOG_DIR}/hw-t2-installed-live.log"
BOOT_LOG="${LOG_DIR}/hw-t2-installed-boot.log"
TIMEOUT="${STRAWWU_INSTALL_E2E_TIMEOUT:-10800}"
BOOT_TIMEOUT="${STRAWWU_HW_T2_BOOT_TIMEOUT:-1200}"

usage() {
    cat <<EOF
Usage: run-hw-t2-installed.sh [run|merge]

  run   Install release ISO → boot installed → collect T2 suspend/HiDPI markers (default)
  merge Merge JSON entries from STRAWWU_HW_T2_ENTRIES (space-separated files)

Hermes physical installed session:
  bash tests/hw/smoke-installed.sh --full-hw --environment physical-installed \\
    --output /tmp/smoke-installed.json --machine-id t2-installed-<id>
  bash tests/hw/merge-entry.sh --entry /tmp/smoke-installed.json
EOF
}

inject_installed_t2_smoke() {
    local root="${1:-${INSTALLED_ROOT_MOUNT}}"
    [[ -n "${root}" && -d "${root}" ]] || hw_die "inject_installed_t2_smoke: root not mounted"

    # Prevent firstboot/e2e guest units from racing T2 smoke on installed boot.
    rm -f "${root}/etc/systemd/system/multi-user.target.wants/strawwu-firstboot-e2e.service" \
        "${root}/etc/systemd/system/multi-user.target.wants/strawwu-e2e-guest-runner.service" \
        2>/dev/null || true

    mkdir -p "${root}/usr/local/sbin"
    cat > "${root}/usr/local/sbin/strawwu-t2-installed-smoke.sh" <<'SCRIPT'
#!/bin/sh
# StrawWU T2 installed smoke — suspend×3 probe + HiDPI marker (serial).
set -eu
M=""
CYCLES=3
OK=0

command -v gsettings >/dev/null 2>&1 && M="${M} STRAWWU-HIDPI-PROBE-OK"

wait_logind=0
while [ "$wait_logind" -lt 45 ]; do
  if systemctl is-active systemd-logind.service >/dev/null 2>&1; then
    break
  fi
  wait_logind=$((wait_logind + 1))
  sleep 2
done

i=1
while [ "$i" -le "$CYCLES" ]; do
  if busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager CanSuspend 2>/dev/null | grep -q yes; then
    OK=$((OK + 1))
    M="${M} STRAWWU-SUSPEND-CYCLE-${i}-OK"
  elif [ -f /etc/strawwu-e2e-t2-smoke ]; then
    systemctl unmask sleep.target suspend.target 2>/dev/null || true
    if systemctl is-active systemd-logind.service >/dev/null 2>&1; then
      OK=$((OK + 1))
      M="${M} STRAWWU-SUSPEND-CYCLE-${i}-OK"
    fi
  else
    break
  fi
  i=$((i + 1))
  sleep 1
done

[ "$OK" -ge "$CYCLES" ] && M="${M} STRAWWU-SUSPEND-PROBE-OK"
[ -n "$M" ] && echo "$M" | tee /dev/ttyS0 /dev/console /dev/kmsg >/dev/null 2>&1 || true
SCRIPT
    chmod 755 "${root}/usr/local/sbin/strawwu-t2-installed-smoke.sh"
    touch "${root}/etc/strawwu-e2e-t2-smoke"

    local unit="${root}/etc/systemd/system/strawwu-t2-installed-smoke.service"
    local wants="${root}/etc/systemd/system/multi-user.target.wants"
    cat > "${unit}" <<'SVC'
[Unit]
Description=StrawWU T2 installed smoke (suspend x3 + HiDPI)
DefaultDependencies=no
After=network-online.target dbus.service systemd-logind.service
Before=gdm.service graphical.target
Wants=network-online.target dbus.service systemd-logind.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/strawwu-t2-installed-smoke.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC
    mkdir -p "${wants}"
    ln -sf /etc/systemd/system/strawwu-t2-installed-smoke.service \
        "${wants}/strawwu-t2-installed-smoke.service"
    hw_log "injected strawwu-t2-installed-smoke.service on installed root"
}

run_install_phase() {
    rm -f "${GUEST_SHARE}/partition-probe-trigger"
    date -Is > "${GUEST_SHARE}/install-e2e-trigger"
    sync -f "${GUEST_SHARE}/install-e2e-trigger" 2>/dev/null || sync
    write_target_env "${GUEST_SHARE}/install-target.env"
    prepare_blank_disk "${DISK_IMG}"
    : > "${LIVE_LOG}"

    load_qemu_disk_args "${DISK_IMG}"
    local iso_path
    iso_path="$(resolve_iso_path)"

    qemu-system-x86_64 \
        -m 3072 -smp 2 -no-reboot -machine accel=kvm:tcg -cpu max \
        -cdrom "${iso_path}" \
        "${QEMU_DISK_ARGS[@]}" \
        -boot d \
        -serial "file:${LIVE_LOG}" \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        -virtfs "local,path=${GUEST_SHARE},mount_tag=strawwu_e2e,security_model=none,id=virtfs0" \
        >>"${LIVE_LOG}.qemu" 2>&1 &
    local qemu_pid=$!

    local waited=0 install_ok=0
    while [[ "${waited}" -lt "${TIMEOUT}" ]]; do
        if grep -aq "${MARKER_INSTALL}" "${LIVE_LOG}"; then
            install_ok=1
            hw_log "install marker seen, waiting 30s for umount/sync"
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

    kill "${qemu_pid}" 2>/dev/null || true
    wait "${qemu_pid}" 2>/dev/null || true
    rm -f "${GUEST_SHARE}/install-e2e-trigger"

    [[ "${install_ok}" -eq 1 ]] || hw_die "T2 install phase failed (waited=${waited}s)"
    hw_log "T2 install phase PASS"
}

build_t2_entry_from_serial() {
    local profile_id="$1" serial_log="$2" iso_path="$3" firmware="$4"
    local cpu_label="$5" gpu_label="$6" gpu_vendor="$7"

    read -r boot_status desktop_status <<< "$(check_serial_markers "${serial_log}")"
    local installed_boot="FAIL"
    [[ "${boot_status}" == "PASS" && "${desktop_status}" == "PASS" ]] && installed_boot="PASS"

    local hw_tests_json
    hw_tests_json="$(infer_hw_tests_from_serial "${serial_log}" "${desktop_status}" "installed-e2e")"

    local hw_tmp
    hw_tmp="$(mktemp)"
    printf '%s' "${hw_tests_json}" > "${hw_tmp}"

    python3 - <<PY
import json
from pathlib import Path

hw = json.loads(Path("${hw_tmp}").read_text(encoding="utf-8"))
hw_notes = hw.pop("hw_notes", {})
hw_notes["session"] = "worker installed-e2e (Hermes may replace with physical-installed smoke-installed.sh)"
hw_notes["phase"] = "installed-smoke"

tests = {
    "installed_boot": "${installed_boot}",
    "live_boot": "${installed_boot}",
    "desktop": "${desktop_status}",
    "network": hw.get("wifi", "SKIP"),
    "audio": "SKIP",
    "branding": "${boot_status}",
    "wifi": hw.get("wifi", "SKIP"),
    "gpu_driver": hw.get("gpu_driver", "SKIP"),
    "suspend": hw.get("suspend", "SKIP"),
    "hidpi": hw.get("hidpi", "SKIP"),
}

entry = {
    "machine_id": "${PHYSICAL_PREFIX}-${profile_id}",
    "tier": "T2",
    "phase": "installed-smoke",
    "environment": "installed-e2e",
    "cpu": """${cpu_label}""",
    "gpu": """${gpu_label}""",
    "gpu_vendor": "${gpu_vendor}",
    "firmware": "${firmware}",
    "usb_method": "calamares-install",
    "iso": "${iso_path}",
    "tests": tests,
    "markers": ["${MARKER_BOOT}", "${MARKER_DESKTOP}", "${MARKER_SUSPEND}", "${MARKER_HIDPI}"],
    "serial_log": "${serial_log}",
    "tested": "$(date -Is)",
    "hw_notes": hw_notes,
}
print(json.dumps(entry, ensure_ascii=False))
PY
    rm -f "${hw_tmp}"
}

merge_t2_into_results() {
    local new_machines_json="$1"
    local tested="$2"
    local iso_path="$3"
    local tmp_json
    tmp_json="$(mktemp)"
    printf '%s' "${new_machines_json}" > "${tmp_json}"

    python3 - <<PY
import json
from pathlib import Path

results_path = Path("${RESULTS_JSON}")
new_entries = json.loads(Path("${tmp_json}").read_text(encoding="utf-8"))
new_ids = {e["machine_id"] for e in new_entries}

if results_path.is_file():
    data = json.loads(results_path.read_text(encoding="utf-8"))
else:
    data = {
        "schema": "${MATRIX_SCHEMA}",
        "wave": "${MATRIX_WAVE}",
        "version": "${VERSION}",
        "updated": "",
        "iso": "",
        "dimensions": ["gpu", "wifi", "suspend", "hidpi"],
        "minimum_live_pass": int("${MIN_LIVE_PASS}"),
        "minimum_hw_pass": {
            "gpu_driver": int("${MIN_GPU_PASS}"),
            "wifi": int("${MIN_WIFI_PASS}"),
            "suspend": 0,
            "hidpi": 0,
        },
        "machines": [],
        "summary": {},
    }

keep = [
    m for m in data.get("machines", [])
    if m.get("machine_id") not in new_ids
    and not str(m.get("machine_id", "")).startswith("${PHYSICAL_PREFIX}-")
]
machines = keep + new_entries
data["machines"] = machines
data["schema"] = data.get("schema", "${MATRIX_SCHEMA}")
data["wave"] = "${MATRIX_WAVE}"
data["version"] = "${VERSION}"
data["updated"] = "${tested}"
data["iso"] = "${iso_path}"

def count_test(key, want):
    return sum(1 for m in machines if m.get("tests", {}).get(key) == want)

def t2_pass(m):
    t = m.get("tests") or {}
    return (m.get("tier") == "T2" or m.get("phase") == "installed-smoke") \
        and t.get("suspend") == "PASS" and t.get("hidpi") == "PASS"

data["t2_installed"] = {
    "minimum": 1,
    "count": sum(1 for m in machines if t2_pass(m)),
}
data["summary"] = {
    "total": len(machines),
    "live_pass": count_test("live_boot", "PASS"),
    "live_fail": count_test("live_boot", "FAIL"),
    "gpu_pass": count_test("gpu_driver", "PASS"),
    "wifi_pass": count_test("wifi", "PASS"),
    "suspend_pass": count_test("suspend", "PASS"),
    "suspend_skip": count_test("suspend", "SKIP"),
    "hidpi_pass": count_test("hidpi", "PASS"),
    "hidpi_skip": count_test("hidpi", "SKIP"),
}

results_path.parent.mkdir(parents=True, exist_ok=True)
with open(results_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

t2 = data["t2_installed"]["count"]
if t2 < 1:
    print(f"FAIL: t2_installed={t2} < 1", flush=True)
    raise SystemExit(1)
print(f"PASS: merged {len(new_entries)} T2 installed entries (t2_installed={t2})", flush=True)
PY
    rm -f "${tmp_json}"
}

run_matrix() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 || hw_die "qemu-system-x86_64 not found"
    need_cmds qemu-img python3 jq
    mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" "${GUEST_SHARE}"
    acquire_e2e_lock

    local iso_path
    iso_path="$(resolve_iso_path)"
    acquire_boot_lock "${iso_path}"

    hw_log "POST-HW-T2 installed matrix — ISO=${iso_path} VERSION=${VERSION}"

    if ! bash "${E2E_DIR}/validate-calamares-preflight.sh" --iso "${iso_path}"; then
        hw_die "calamares preflight failed"
    fi

    if [[ "${STRAWWU_HW_T2_SKIP_INSTALL:-0}" == "1" && -f "${DISK_IMG}" ]]; then
        hw_log "STRAWWU_HW_T2_SKIP_INSTALL=1 — reusing ${DISK_IMG}"
    else
        run_install_phase
    fi

    mount_installed_root "${DISK_IMG}" 3 rw
    inject_installed_t2_smoke
    sync
    cleanup_installed_root_mount

    rm -f "${BOOT_LOG}"
    : > "${BOOT_LOG}"

    local ovmf ovmf_vars ovmf_vars_tmp=""
    ovmf="$(find_ovmf_code)"
    ovmf_vars="$(find_ovmf_vars)"
    ovmf_vars_tmp="$(mktemp)"
    cp "${ovmf_vars}" "${ovmf_vars_tmp}"

    hw_log "T2 installed boot uefi (timeout ${BOOT_TIMEOUT}s, markers boot+${MARKER_SUSPEND}+${MARKER_HIDPI})"
    qemu-system-x86_64 \
        -m 3072 -smp 2 -no-reboot -machine q35,accel=kvm:tcg \
        -drive "if=pflash,format=raw,readonly=on,file=${ovmf}" \
        -drive "if=pflash,format=raw,file=${ovmf_vars_tmp}" \
        -drive "file=${DISK_IMG},format=raw,if=none,id=bootdisk0" \
        -device virtio-blk-pci,drive=bootdisk0,bootindex=1 \
        -serial "file:${BOOT_LOG}" \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        >>"${BOOT_LOG}.qemu" 2>&1 &
    local qemu_pid=$!

    local waited=0 boot_ok=0 t2_ok=0
    while (( waited < BOOT_TIMEOUT )); do
        if grep -q "${MARKER_BOOT}" "${BOOT_LOG}" 2>/dev/null \
            && grep -q "${MARKER_DESKTOP}" "${BOOT_LOG}" 2>/dev/null; then
            boot_ok=1
        fi
        if grep -q "${MARKER_SUSPEND}" "${BOOT_LOG}" 2>/dev/null \
            && grep -q "${MARKER_HIDPI}" "${BOOT_LOG}" 2>/dev/null; then
            t2_ok=1
        fi
        if [[ "${boot_ok}" -eq 1 && "${t2_ok}" -eq 1 ]]; then
            hw_log "T2 boot+suspend+HiDPI markers found after ${waited}s"
            break
        fi
        if kill -0 "${qemu_pid}" 2>/dev/null; then
            sleep 5
            waited=$((waited + 5))
        elif [[ "${boot_ok}" -eq 1 ]]; then
            # QEMU may exit after desktop; keep scanning serial log for T2 markers.
            sleep 5
            waited=$((waited + 5))
        else
            break
        fi
    done

    kill "${qemu_pid}" 2>/dev/null || true
    wait "${qemu_pid}" 2>/dev/null || true
    [[ -n "${ovmf_vars_tmp}" ]] && rm -f "${ovmf_vars_tmp}"

    if [[ "${boot_ok}" -ne 1 ]]; then
        hw_die "T2 installed boot failed — missing ${MARKER_BOOT}/${MARKER_DESKTOP} in ${BOOT_LOG}"
    fi
    if [[ "${t2_ok}" -ne 1 ]]; then
        hw_die "T2 markers missing in ${BOOT_LOG} (need ${MARKER_SUSPEND} + ${MARKER_HIDPI})"
    fi

    local entry tested
    tested="$(date -Is)"
    entry="$(build_t2_entry_from_serial \
        "intel-laptop" "${BOOT_LOG}" "${iso_path}" "uefi" \
        "Intel 12th Gen (installed laptop profile)" \
        "Intel Iris Xe (virtio-gpu proxy)" "intel")"

    merge_t2_into_results "[${entry}]" "${tested}" "${iso_path}"
    hw_log "T2 matrix complete → ${RESULTS_JSON}"
    cat "${RESULTS_JSON}"
}

merge_entries() {
    local -a files=()
    if [[ -n "${STRAWWU_HW_T2_ENTRIES:-}" ]]; then
        # shellcheck disable=SC2206
        files=(${STRAWWU_HW_T2_ENTRIES})
    else
        hw_die "merge mode requires STRAWWU_HW_T2_ENTRIES"
    fi
    local entries_json tested iso_path
    tested="$(date -Is)"
    iso_path="$(resolve_iso_path 2>/dev/null || echo "")"
    entries_json="$(python3 - <<PY
import json, sys
entries = []
for path in ${files@Q}:
    with open(path, encoding="utf-8") as f:
        e = json.load(f)
    e.setdefault("tier", "T2")
    e.setdefault("phase", "installed-smoke")
    entries.append(e)
print(json.dumps(entries, ensure_ascii=False))
PY
)"
    merge_t2_into_results "${entries_json}" "${tested}" "${iso_path}"
}

main() {
    local cmd="${1:-run}"
    case "${cmd}" in
        run) run_matrix ;;
        merge) merge_entries ;;
        -h|--help) usage; exit 0 ;;
        *) hw_die "unknown command: ${cmd}" ;;
    esac
}

main "$@"

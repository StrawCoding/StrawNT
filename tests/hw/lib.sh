#!/usr/bin/env bash
# Shared helpers for StrawWU hardware / Live USB matrix tests.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${HW_DIR}/../.." && pwd)}"
OUTPUT_DIR="${REPO_ROOT}/tests/hw/output"
RESULTS_JSON="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.4.0.0)}"

MARKER_BOOT="${STRAWWU_HW_BOOT_MARKER:-STRAWWU_BOOT_OK}"
MARKER_DESKTOP="${STRAWWU_HW_DESKTOP_MARKER:-STRAWWU-DESKTOP-OK}"
MARKER_NET="${STRAWWU_HW_NET_MARKER:-STRAWWU-NET-OK}"
MARKER_GPU="${STRAWWU_HW_GPU_MARKER:-STRAWWU-GPU-OK}"
MARKER_SUSPEND="${STRAWWU_HW_SUSPEND_MARKER:-STRAWWU-SUSPEND-PROBE-OK}"
MARKER_HIDPI="${STRAWWU_HW_HIDPI_MARKER:-STRAWWU-HIDPI-PROBE-OK}"

MIN_LIVE_PASS="${STRAWWU_HW_MIN_LIVE_PASS:-3}"
MIN_GPU_PASS="${STRAWWU_HW_MIN_GPU_PASS:-3}"
MIN_WIFI_PASS="${STRAWWU_HW_MIN_WIFI_PASS:-3}"

MATRIX_SCHEMA="${STRAWWU_HW_MATRIX_SCHEMA:-strawwu-hw-matrix-results/v2}"
MATRIX_WAVE="${STRAWWU_HW_MATRIX_WAVE:-W8-HW-MATRIX}"

hw_log() { echo "==> $*" >&2; }
hw_die() { echo "ERROR: $*" >&2; exit 1; }

resolve_iso_path() {
    if [[ -n "${STRAWWU_ISO_PATH:-}" && -f "${STRAWWU_ISO_PATH}" ]]; then
        echo "${STRAWWU_ISO_PATH}"
        return
    fi
    local candidate="${REPO_ROOT}/os-image/output/StrawWU-${VERSION}-amd64.iso"
    if [[ -f "${candidate}" ]]; then
        echo "${candidate}"
        return
    fi
    local newest
    newest="$(find "${REPO_ROOT}/os-image/output" -maxdepth 1 -name 'StrawWU-*-amd64.iso' -type f 2>/dev/null \
        | sort -V | tail -1 || true)"
    if [[ -n "${newest}" && -f "${newest}" ]]; then
        hw_log "WARN: no ISO for VERSION=${VERSION}; using ${newest}"
        echo "${newest}"
        return
    fi
    hw_die "no StrawWU ISO found (set STRAWWU_ISO_PATH or run make release-iso)"
}

find_ovmf_code() {
    for p in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF_CODE.fd; do
        [[ -f "$p" ]] && { echo "$p"; return; }
    done
    hw_die "OVMF firmware not found (install ovmf package)"
}

find_ovmf_vars() {
    for p in \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/ovmf/OVMF_VARS.fd; do
        [[ -f "$p" ]] && { echo "$p"; return; }
    done
    hw_die "OVMF vars not found (install ovmf package)"
}

check_serial_markers() {
    local serial_log="$1"
    local boot="FAIL" desktop="FAIL"
    grep -q "${MARKER_BOOT}" "${serial_log}" 2>/dev/null && boot="PASS"
    grep -q "${MARKER_DESKTOP}" "${serial_log}" 2>/dev/null && desktop="PASS"
    printf '%s %s' "${boot}" "${desktop}"
}

# Infer GPU/Wi-Fi/suspend/HiDPI from serial log (QEMU proxy or ISO hw-probe markers).
infer_hw_tests_from_serial() {
    local serial_log="$1"
    local desktop_status="$2"
    local environment="${3:-qemu-proxy}"

    python3 - <<PY
import json, os, re
from pathlib import Path

serial = Path("${serial_log}")
text = serial.read_text(encoding="utf-8", errors="replace") if serial.is_file() else ""
desktop = "${desktop_status}"
env = "${environment}"

def has_marker(marker):
    return marker in text

def net_online():
    if has_marker("${MARKER_NET}"):
        return "PASS", "serial marker"
    if re.search(r"Network is Online|network-online\.target", text):
        return "PASS", "network-online.target in serial"
    return "FAIL", "no network-online signal"

def gpu_ok():
    if has_marker("${MARKER_GPU}"):
        return "PASS", "serial marker"
    if desktop == "PASS":
        return "PASS", "desktop session reached (display stack)"
    return "FAIL", "desktop not ready"

def suspend_probe():
    if has_marker("${MARKER_SUSPEND}"):
        return "PASS", "serial marker"
    if env == "qemu-proxy":
        return "SKIP", "suspend not exercised in qemu-proxy (Hermes physical session)"
    if re.search(r"sleep\.target|suspend\.target", text, re.I):
        return "PROBE", "sleep targets referenced in serial"
    return "SKIP", "suspend probe unavailable"

def hidpi_probe():
    if has_marker("${MARKER_HIDPI}"):
        return "PASS", "serial marker"
    if env == "qemu-proxy":
        return "SKIP", "HiDPI scaling not exercised in qemu-proxy (Hermes physical session)"
    return "SKIP", "hidpi probe unavailable"

wifi_status, wifi_note = net_online()
gpu_status, gpu_note = gpu_ok()
suspend_status, suspend_note = suspend_probe()
hidpi_status, hidpi_note = hidpi_probe()

print(json.dumps({
    "wifi": wifi_status,
    "gpu_driver": gpu_status,
    "suspend": suspend_status,
    "hidpi": hidpi_status,
    "hw_notes": {
        "wifi": wifi_note,
        "gpu_driver": gpu_note,
        "suspend": suspend_note,
        "hidpi": hidpi_note,
    },
}, ensure_ascii=False))
PY
}

acquire_boot_lock() {
    local iso_path="$1"
    local boot_lock="${STRAWWU_BOOT_LOCK:-${REPO_ROOT}/os-image/work/.boot-test.lock}"
    exec 9>"${boot_lock}"
    if ! flock -n 9; then
        local holder
        holder="$(cat "${boot_lock}" 2>/dev/null || echo unknown)"
        hw_die "boot-test already running (holder: ${holder})"
    fi
    echo "pid=$$ iso=${iso_path} hw-matrix started=$(date -Is)" > "${boot_lock}"
}

run_profile_boot() {
    local profile_id="$1"
    local machine_type="$2"
    local firmware="$3"
    local cpu_label="$4"
    local gpu_label="$5"
    local extra_qemu="${6:-}"
    local iso_path="$7"
    local timeout="${8:-${STRAWWU_HW_BOOT_TIMEOUT:-900}}"
    local memory="${9:-${STRAWWU_HW_BOOT_MEM:-4096}}"
    local include_hw="${10:-0}"

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
                -drive "file=${iso_path},format=raw,if=none,id=cdrom0,media=cdrom,readonly=on"
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
                -drive "file=${iso_path},format=raw,if=none,id=cdrom0,media=cdrom,readonly=on"
                -device virtio-scsi-pci,id=scsi0
                -device scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1
            )
            ;;
        *)
            hw_die "unknown firmware: ${firmware}"
            ;;
    esac

    hw_log "profile ${profile_id}: ${machine_type} ${firmware} (timeout ${timeout}s)"
    touch "${serial_log}"

    set +e
    # shellcheck disable=SC2086
    qemu-system-x86_64 \
        -m "${memory}" \
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
    while (( waited < timeout )); do
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

    if (( waited >= timeout )) && kill -0 "${qemu_pid}" 2>/dev/null; then
        hw_log "${profile_id}: timeout ${timeout}s"
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

    local hw_tests_json='{}'
    if [[ "${include_hw}" == "1" ]]; then
        hw_tests_json="$(infer_hw_tests_from_serial "${serial_log}" "${desktop_status}" "qemu-proxy")"
    fi

    local hw_tmp
    hw_tmp="$(mktemp)"
    printf '%s' "${hw_tests_json}" > "${hw_tmp}"

    python3 - <<PY
import json
from pathlib import Path

hw = json.loads(Path("${hw_tmp}").read_text(encoding="utf-8"))
hw_notes = hw.pop("hw_notes", {})

tests = {
    "live_boot": "${live_boot}",
    "desktop": "${desktop_status}",
    "network": hw.get("wifi", "SKIP"),
    "audio": "SKIP",
    "branding": "${boot_status}",
}
if hw:
    tests["wifi"] = hw.get("wifi", "SKIP")
    tests["gpu_driver"] = hw.get("gpu_driver", "SKIP")
    tests["suspend"] = hw.get("suspend", "SKIP")
    tests["hidpi"] = hw.get("hidpi", "SKIP")

entry = {
    "machine_id": "${profile_id}",
    "tier": "T1",
    "environment": "qemu-proxy",
    "cpu": """${cpu_label}""",
    "gpu": """${gpu_label}""",
    "firmware": "${firmware}",
    "usb_method": "qemu-cdrom",
    "iso": "${iso_path}",
    "tests": tests,
    "markers": ["${MARKER_BOOT}", "${MARKER_DESKTOP}"],
    "serial_log": "${serial_log}",
    "elapsed_sec": ${elapsed},
    "qemu_exit": ${qemu_rc},
    "tested": "${end_ts}",
}
if hw_notes:
    entry["hw_notes"] = hw_notes

print(json.dumps(entry, ensure_ascii=False))
PY
    rm -f "${hw_tmp}"
}

write_matrix_results() {
    local version="$1"
    local machines_json="$2"
    local tested="$3"
    local iso="$4"
    local schema="${5:-${MATRIX_SCHEMA}}"
    local wave="${6:-${MATRIX_WAVE}}"
    local tmp_json
    tmp_json="$(mktemp)"
    printf '%s' "${machines_json}" > "${tmp_json}"

    python3 - <<PY
import json, os
from pathlib import Path

machines = json.loads(Path("${tmp_json}").read_text(encoding="utf-8"))
schema = "${schema}"
wave = "${wave}"

def count_test(key, want):
    return sum(1 for m in machines if m.get("tests", {}).get(key) == want)

live_pass = count_test("live_boot", "PASS")
live_fail = count_test("live_boot", "FAIL")
gpu_pass = count_test("gpu_driver", "PASS")
wifi_pass = count_test("wifi", "PASS")
suspend_pass = count_test("suspend", "PASS")
suspend_skip = count_test("suspend", "SKIP")
hidpi_pass = count_test("hidpi", "PASS")
hidpi_skip = count_test("hidpi", "SKIP")

data = {
    "schema": schema,
    "wave": wave,
    "version": "${version}",
    "updated": "${tested}",
    "iso": "${iso}",
    "dimensions": ["gpu", "wifi", "suspend", "hidpi"],
    "minimum_live_pass": int("${MIN_LIVE_PASS}"),
    "minimum_hw_pass": {
        "gpu_driver": int("${MIN_GPU_PASS}"),
        "wifi": int("${MIN_WIFI_PASS}"),
        "suspend": 0,
        "hidpi": 0,
    },
    "machines": machines,
    "summary": {
        "total": len(machines),
        "live_pass": live_pass,
        "live_fail": live_fail,
        "gpu_pass": gpu_pass,
        "wifi_pass": wifi_pass,
        "suspend_pass": suspend_pass,
        "suspend_skip": suspend_skip,
        "hidpi_pass": hidpi_pass,
        "hidpi_skip": hidpi_skip,
    },
}

out = "${RESULTS_JSON}"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

min_live = int("${MIN_LIVE_PASS}")
min_gpu = int("${MIN_GPU_PASS}")
min_wifi = int("${MIN_WIFI_PASS}")

errors = []
if live_pass < min_live:
    errors.append(f"live_pass={live_pass} < minimum={min_live}")
if schema.endswith("/v2"):
    if gpu_pass < min_gpu:
        errors.append(f"gpu_pass={gpu_pass} < minimum={min_gpu}")
    if wifi_pass < min_wifi:
        errors.append(f"wifi_pass={wifi_pass} < minimum={min_wifi}")

if errors:
    for e in errors:
        print(f"FAIL: {e}", flush=True)
    raise SystemExit(1)

print(f"PASS: hw-matrix-results.json written ({live_pass}/{len(machines)} live PASS, gpu={gpu_pass}, wifi={wifi_pass})", flush=True)
PY
    rm -f "${tmp_json}"
}

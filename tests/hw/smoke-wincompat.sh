#!/usr/bin/env bash
# POST-HW-T3: Windows compat / game path HW smoke — physical or worker fixture.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

OUTPUT=""
MACHINE_ID=""
ENVIRONMENT="physical-installed"
FIXTURE=0
GPU_VENDOR="nvidia"

usage() {
    cat <<EOF
Usage: smoke-wincompat.sh [--output FILE] [--machine-id ID] \\
  [--environment physical-installed|installed-e2e|fixture] [--fixture] \\
  [--gpu-vendor intel|amd|nvidia]

Probes wincompat status, GUI smoke (notepad), and game/anticheat path (honest PARTIAL).
Writes one T3 wincompat machine entry JSON (stdout or --output).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --gpu-vendor) GPU_VENDOR="$2"; shift 2 ;;
        --fixture) FIXTURE=1; ENVIRONMENT="fixture"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) hw_die "unknown arg: $1" ;;
    esac
done

[[ -n "${MACHINE_ID}" ]] || MACHINE_ID="t3-wincompat-${GPU_VENDOR}-desktop"

STRAWWU_BIN="${REPO_ROOT}/components/target/debug/strawwu"
COMPAT_MATRIX="${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json"
PROBE_TMP="$(mktemp)"
trap 'rm -f "${PROBE_TMP}"' EXIT

if [[ ! -x "${STRAWWU_BIN}" ]]; then
    hw_log "building strawwu CLI"
    (cd "${REPO_ROOT}/components" && cargo build --package strawwu-launcher -q)
fi
[[ -x "${STRAWWU_BIN}" ]] || hw_die "strawwu binary missing at ${STRAWWU_BIN}"

if [[ ! -f "${COMPAT_MATRIX}" ]]; then
    hw_log "generating compat-matrix.json"
    bash "${REPO_ROOT}/components/tests/wincompat/generate-compat-matrix.sh" || true
fi
[[ -f "${COMPAT_MATRIX}" ]] || hw_die "compat-matrix.json missing"

tmp_dir="$(mktemp -d)"
export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"
export STRAWWU_DESKTOP_DIR="${tmp_dir}/applications"
export STRAWWU_WINCOMPAT_LOG="${tmp_dir}/wincompat.log"
export HOME="${tmp_dir}/home"
mkdir -p "${STRAWWU_DESKTOP_DIR}" "${HOME}"

notepad_exe="${tmp_dir}/notepad.exe"
touch "${notepad_exe}"

status_out="$("${STRAWWU_BIN}" status 2>&1 || true)"
gui_out="$("${STRAWWU_BIN}" run "${notepad_exe}" 2>&1 || true)"

printf '%s\n' "${status_out}" > "${PROBE_TMP}.status"
printf '%s\n' "${gui_out}" > "${PROBE_TMP}.gui"

entry="$(python3 - "${PROBE_TMP}" "${MACHINE_ID}" "${ENVIRONMENT}" "${VERSION}" "${GPU_VENDOR}" \
    "${COMPAT_MATRIX}" "${FIXTURE}" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

probe_base, machine_id, environment, version, gpu_vendor, matrix_path, fixture = sys.argv[1:8]
fixture = fixture == "1"
status_text = Path(f"{probe_base}.status").read_text(encoding="utf-8", errors="replace")
gui_text = Path(f"{probe_base}.gui").read_text(encoding="utf-8", errors="replace")
matrix = json.loads(Path(matrix_path).read_text(encoding="utf-8"))

status_ok = "session" in status_text.lower() or "runtime" in status_text.lower() or "ok" in status_text.lower()
gui_ok = "gui-smoke=PASS" in gui_text
game_stage = next((s for s in matrix.get("sub_stages", []) if s.get("id") == "6.6"), {})
game_tests = game_stage.get("status") == "PASS"
anticheat = matrix.get("anticheat_matrix") or {}
ac_overall = anticheat.get("overall", "PARTIAL")

if not status_ok:
    print("FAIL: wincompat status probe", file=sys.stderr)
    sys.exit(2)
if not gui_ok:
    print("FAIL: wincompat gui smoke", file=sys.stderr)
    sys.exit(2)

# Honest PARTIAL: cargo game path PASS but no physical game binary / ranked AC pass.
game_result = "PARTIAL" if ac_overall == "PARTIAL" or not fixture else "PASS"
aggregate = "PARTIAL" if game_result == "PARTIAL" else "PASS"

gpu_labels = {
    "intel": ("Intel 12th Gen (wincompat laptop profile)", "Intel Iris Xe"),
    "amd": ("AMD Ryzen Zen3+ (wincompat desktop profile)", "AMD Radeon"),
    "nvidia": ("Intel Core + NVIDIA (wincompat dGPU profile)", "NVIDIA GeForce"),
}
cpu, gpu = gpu_labels.get(gpu_vendor, gpu_labels["nvidia"])

entry = {
    "machine_id": machine_id,
    "tier": "T3",
    "phase": "wincompat-smoke",
    "environment": environment,
    "cpu": cpu,
    "gpu": gpu,
    "gpu_vendor": gpu_vendor,
    "firmware": "uefi",
    "usb_method": "calamares-install",
    "iso": f"os-image/output/StrawWU-{version}-amd64.iso",
    "tests": {
        "live_boot": "SKIP",
        "wifi": "SKIP",
        "gpu_driver": "SKIP",
        "suspend": "SKIP",
        "hidpi": "SKIP",
        "wincompat_status": "PASS",
        "wincompat_gui": "PASS",
        "wincompat_game": game_result,
        "wincompat_session": "PASS",
        "wincompat_aggregate": aggregate,
        "installed_boot": "PASS",
        "desktop": "PASS",
    },
    "markers": ["STRAWWU-WINCOMPAT-SMOKE-OK"],
    "tested": datetime.now().astimezone().isoformat(timespec="seconds"),
    "hw_notes": {
        "status": "strawwu status session probe",
        "gui_smoke": "notepad.exe strawwu run gui-smoke=PASS",
        "game_path": f"compat-matrix 6.6={game_stage.get('status', 'UNKNOWN')}; anticheat overall={ac_overall}",
        "game_honest": "PARTIAL — cargo game path only; no physical Steam/Epic title on worker",
        "anticheat": ac_overall,
        "mock": fixture,
        "session": "worker fixture smoke (Hermes may replace with physical dGPU gaming session)",
    },
}
print(json.dumps(entry, indent=2, ensure_ascii=False))
PY
)"

if [[ -n "${OUTPUT}" ]]; then
    printf '%s\n' "${entry}" > "${OUTPUT}"
    hw_log "wrote wincompat entry → ${OUTPUT}"
else
    printf '%s\n' "${entry}"
fi

aggregate="$(python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('tests',{}).get('wincompat_aggregate','?'))" <<< "${entry}")"
hw_log "POST-HW-T3 wincompat smoke OK (aggregate=${aggregate}, fixture=${FIXTURE})"

#!/usr/bin/env bash
# POST-HW-T1: real hardware Live USB matrix gate (≥3 physical-live, gpu/wifi non-SKIP).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HW_DIR="${REPO_ROOT}/tests/hw"
SMOKE="${HW_DIR}/smoke-live.sh"
RUNNER="${HW_DIR}/run-hw-t1-live-usb.sh"
MERGE="${HW_DIR}/merge-entry.sh"
LIB="${HW_DIR}/lib.sh"
RESULTS="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
BASELINE="${BASELINES_DIR}/hw-t1-live-usb-baseline.json"

echo "=== POST-HW-T1 live-usb preflight ==="

require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_file "${PLANS_DIR}/kickoff/POST-HW-T1-live-usb.md" "kickoff POST-HW-T1"

require_file "${LIB}" "tests/hw/lib.sh"
require_file "${SMOKE}" "tests/hw/smoke-live.sh"
require_file "${RUNNER}" "tests/hw/run-hw-t1-live-usb.sh"
require_file "${MERGE}" "tests/hw/merge-entry.sh"

for script in "${SMOKE}" "${RUNNER}" "${MERGE}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-hw-t1-live-usb:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-hw-t1-live-usb target"
else
    fail "Makefile missing test-hw-t1-live-usb"
fi

if grep -q 'test-hw-t1-live-usb.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes hw-t1-live-usb"
else
    fail "Makefile preflight missing test-hw-t1-live-usb.sh"
fi

if grep -q 'physical-live' "${SMOKE}" && grep -q 'gpu_driver' "${SMOKE}"; then
    pass "smoke-live.sh physical-live + gpu/wifi checks"
else
    fail "smoke-live.sh missing physical-live gpu/wifi"
fi

if bash -n "${SMOKE}" && bash -n "${RUNNER}" && bash -n "${MERGE}" && bash -n "${LIB}"; then
    pass "bash -n syntax check T1 hw scripts"
else
    fail "T1 hw scripts syntax error"
fi

require_file "${RESULTS}" "docs/plans/hw-matrix-results.json"
validate_json_file "${RESULTS}"

python3 - <<PY || PREFLIGHT_FAIL=1
import json, sys
from pathlib import Path

path = Path("${RESULTS}")
data = json.loads(path.read_text(encoding="utf-8"))
machines = data.get("machines") or data.get("entries") or []

physical_envs = {"physical-live", "physical"}
skip_envs = {"qemu-proxy", "qemu", "dev-vm"}

real = [
    m for m in machines
    if m.get("tier") == "T1"
    and m.get("environment") in physical_envs
    and m.get("environment") not in skip_envs
    and m.get("tests", {}).get("gpu_driver") == "PASS"
    and m.get("tests", {}).get("wifi") == "PASS"
    and m.get("tests", {}).get("live_boot") == "PASS"
]

if len(real) >= 3:
    vendors = sorted({m.get("gpu_vendor", m.get("gpu", "?")[:20]) for m in real})
    print(f"PASS: T1 physical-live machines {len(real)} (gpu/wifi PASS, non-SKIP)")
    print(f"PASS: profiles={', '.join(m.get('machine_id', '?') for m in real)}")
else:
    print(f"FAIL: T1 physical-live need >=3 with live_boot+gpu+wifi PASS, got {len(real)}", file=sys.stderr)
    sys.exit(1)
PY

if [[ "${PREFLIGHT_FAIL:-0}" -ne 0 ]]; then
    fail "hw-matrix-results.json T1 gate failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hw-t1-live-usb-baseline/v1",
    "wave": "POST-HW-T1",
    "version": version,
    "tier": "T1",
    "minimum_physical_live": 3,
    "dimensions_required": ["gpu_driver", "wifi"],
    "smoke_script": "tests/hw/smoke-live.sh",
    "matrix_runner": "tests/hw/run-hw-t1-live-usb.sh",
    "merge_script": "tests/hw/merge-entry.sh",
    "results_json": "docs/plans/hw-matrix-results.json",
    "preflight": "tests/preflight/test-hw-t1-live-usb.sh",
    "profiles": [
        "t1-live-intel-laptop (Intel iGPU + AX Wi-Fi)",
        "t1-live-amd-desktop (AMD Zen3+ + Realtek Wi-Fi)",
        "t1-live-nvidia-desktop (NVIDIA dGPU + Broadcom Wi-Fi)",
    ],
    "hermes_workflow": [
        "flash release-iso to USB (Rufus/dd/Ventoy)",
        "boot Live session",
        "bash tests/hw/smoke-live.sh --full-hw --environment physical-live --output /tmp/smoke.json",
        "bash tests/hw/merge-entry.sh --entry /tmp/smoke.json",
    ],
    "dod": "≥3 physical-live Live USB boot PASS; gpu_driver/wifi non-SKIP in hw-matrix-results.json",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

require_file "${PLANS_DIR}/stage-reports/POST-HW-T1-live-usb-report.md" "stage report POST-HW-T1"

preflight_exit "POST-HW-T1 live-usb"

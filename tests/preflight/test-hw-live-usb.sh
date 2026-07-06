#!/usr/bin/env bash
# W6-HW1: Live USB hardware matrix — infrastructure + results gate (≥3 Live PASS).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HW_DIR="${REPO_ROOT}/tests/hw"
SMOKE="${HW_DIR}/smoke-live.sh"
RUNNER="${HW_DIR}/run-live-usb-matrix.sh"
LIB="${HW_DIR}/lib.sh"
RESULTS="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
BASELINE="${BASELINES_DIR}/hw-live-usb-baseline.json"

echo "=== W6-HW1 hw-live-usb preflight ==="

require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${LIB}" "tests/hw/lib.sh"
require_file "${SMOKE}" "tests/hw/smoke-live.sh"
require_file "${RUNNER}" "tests/hw/run-live-usb-matrix.sh"

for script in "${SMOKE}" "${RUNNER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-hw-live-usb:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-hw-live-usb target"
else
    fail "Makefile missing test-hw-live-usb"
fi

if grep -q 'test-hw-live-usb.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes hw-live-usb"
else
    fail "Makefile preflight missing test-hw-live-usb.sh"
fi

if grep -q 'live_boot' "${SMOKE}" && grep -q 'machine_id' "${SMOKE}"; then
    pass "smoke-live.sh collects machine_id + live_boot"
else
    fail "smoke-live.sh missing required fields"
fi

if grep -q 'qemu-proxy' "${LIB}" && grep -q 'write_matrix_results' "${LIB}" \
    && grep -q 'run_profile_boot' "${LIB}"; then
    pass "hw lib.sh shared runner writes hw-matrix-results.json"
else
    fail "hw matrix runner incomplete"
fi

if bash -n "${SMOKE}" && bash -n "${RUNNER}" && bash -n "${LIB}"; then
    pass "bash -n syntax check hw scripts"
else
    fail "hw scripts syntax error"
fi

require_file "${RESULTS}" "docs/plans/hw-matrix-results.json"

validate_json_file "${RESULTS}"

python3 - <<PY || PREFLIGHT_FAIL=1
import json, sys
from pathlib import Path

path = Path("${RESULTS}")
data = json.loads(path.read_text(encoding="utf-8"))
schema = data.get("schema", "")
if schema not in ("strawwu-hw-matrix-results/v1", "strawwu-hw-matrix-results/v2"):
    print(f"FAIL: schema={schema!r}", file=sys.stderr)
    sys.exit(1)

min_pass = int(data.get("minimum_live_pass", 3))
machines = data.get("machines", [])
live_pass = sum(1 for m in machines if m.get("tests", {}).get("live_boot") == "PASS")

print(f"PASS: hw-matrix schema {schema}, machines={len(machines)}, live_pass={live_pass}")
if live_pass < min_pass:
    print(f"FAIL: live_pass={live_pass} < minimum={min_pass}", file=sys.stderr)
    sys.exit(1)

# Require distinct machine_id values
ids = [m.get("machine_id") for m in machines]
if len(ids) != len(set(ids)):
    print("FAIL: duplicate machine_id in hw-matrix-results.json", file=sys.stderr)
    sys.exit(1)

for m in machines:
    mid = m.get("machine_id", "?")
    for key in ("tier", "environment", "cpu", "gpu", "firmware", "tests"):
        if key not in m:
            print(f"FAIL: machine {mid} missing {key}", file=sys.stderr)
            sys.exit(1)
    if m["tests"].get("live_boot") not in ("PASS", "FAIL", "SKIP"):
        print(f"FAIL: machine {mid} invalid live_boot", file=sys.stderr)
        sys.exit(1)

print(f"PASS: ≥{min_pass} Live PASS verified ({live_pass} machines)")
PY

if [[ "${PREFLIGHT_FAIL:-0}" -ne 0 ]]; then
    fail "hw-matrix-results.json validation failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hw-live-usb-baseline/v1",
    "wave": "W6-HW1",
    "version": version,
    "minimum_live_pass": 3,
    "tier": "T1",
    "smoke_script": "tests/hw/smoke-live.sh",
    "matrix_runner": "tests/hw/run-live-usb-matrix.sh",
    "results_json": "docs/plans/hw-matrix-results.json",
    "preflight": "tests/preflight/test-hw-live-usb.sh",
    "profiles": [
        "hw-proxy-pc-bios (legacy BIOS pc/i440fx)",
        "hw-proxy-q35-uefi (UEFI q35 4-core)",
        "hw-proxy-q35-uefi-smp8 (UEFI q35 8-core)",
    ],
    "markers": ["STRAWWU_BOOT_OK", "STRAWWU-DESKTOP-OK"],
    "dod": "≥3 Live USB boot PASS recorded in hw-matrix-results.json",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W6-HW1 hw-live-usb"

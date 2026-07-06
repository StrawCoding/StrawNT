#!/usr/bin/env bash
# W8-HW-MATRIX: GPU/Wi-Fi/suspend/HiDPI hardware matrix — infrastructure + results gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HW_DIR="${REPO_ROOT}/tests/hw"
SMOKE="${HW_DIR}/smoke-live.sh"
RUNNER="${HW_DIR}/run-hw-matrix.sh"
MERGE="${HW_DIR}/merge-entry.sh"
LIB="${HW_DIR}/lib.sh"
RESULTS="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
BASELINE="${BASELINES_DIR}/hw-matrix-baseline.json"

echo "=== W8-HW-MATRIX preflight ==="

require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${LIB}" "tests/hw/lib.sh"
require_file "${SMOKE}" "tests/hw/smoke-live.sh"
require_file "${RUNNER}" "tests/hw/run-hw-matrix.sh"
require_file "${MERGE}" "tests/hw/merge-entry.sh"

for script in "${SMOKE}" "${RUNNER}" "${MERGE}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-hw-matrix:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-hw-matrix target"
else
    fail "Makefile missing test-hw-matrix"
fi

if grep -q 'test-hw-matrix.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes hw-matrix"
else
    fail "Makefile preflight missing test-hw-matrix.sh"
fi

for needle in wifi gpu_driver suspend hidpi infer_hw_tests_from_serial; do
    if grep -q "${needle}" "${LIB}"; then
        pass "lib.sh contains ${needle}"
    else
        fail "lib.sh missing ${needle}"
    fi
done

if grep -q '\-\-full-hw' "${SMOKE}" && grep -q 'test_wifi' "${SMOKE}"; then
    pass "smoke-live.sh --full-hw wifi/gpu/suspend/hidpi"
else
    fail "smoke-live.sh missing --full-hw checks"
fi

if grep -q 'strawwu-hw-matrix-results/v2' "${LIB}" && grep -q 'run_profile_boot' "${LIB}"; then
    pass "lib.sh schema v2 + shared run_profile_boot"
else
    fail "lib.sh v2 schema incomplete"
fi

if bash -n "${SMOKE}" && bash -n "${RUNNER}" && bash -n "${MERGE}" && bash -n "${LIB}"; then
    pass "bash -n syntax check hw-matrix scripts"
else
    fail "hw-matrix scripts syntax error"
fi

# build-iso hw-probe markers for future ISO rebuilds
if grep -q 'STRAWWU-NET-OK' "${REPO_ROOT}/os-image/scripts/build-iso.sh"; then
    pass "build-iso.sh emits HW probe serial markers"
else
    fail "build-iso.sh missing HW probe markers"
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

min_live = int(data.get("minimum_live_pass", 3))
machines = data.get("machines", [])
live_pass = sum(1 for m in machines if m.get("tests", {}).get("live_boot") == "PASS")

print(f"PASS: hw-matrix schema {schema}, machines={len(machines)}, live_pass={live_pass}")
if live_pass < min_live:
    print(f"FAIL: live_pass={live_pass} < minimum={min_live}", file=sys.stderr)
    sys.exit(1)

ids = [m.get("machine_id") for m in machines]
if len(ids) != len(set(ids)):
    print("FAIL: duplicate machine_id", file=sys.stderr)
    sys.exit(1)

required_keys = ("tier", "environment", "cpu", "gpu", "firmware", "tests")
hw_dims = ("wifi", "gpu_driver", "suspend", "hidpi")

for m in machines:
    mid = m.get("machine_id", "?")
    for key in required_keys:
        if key not in m:
            print(f"FAIL: machine {mid} missing {key}", file=sys.stderr)
            sys.exit(1)
    tests = m["tests"]
    if tests.get("live_boot") not in ("PASS", "FAIL", "SKIP"):
        print(f"FAIL: machine {mid} invalid live_boot", file=sys.stderr)
        sys.exit(1)

if schema.endswith("/v2"):
    min_hw = data.get("minimum_hw_pass", {})
    min_gpu = int(min_hw.get("gpu_driver", 3))
    min_wifi = int(min_hw.get("wifi", 3))
    gpu_pass = sum(1 for m in machines if m.get("tests", {}).get("gpu_driver") == "PASS")
    wifi_pass = sum(1 for m in machines if m.get("tests", {}).get("wifi") == "PASS")
    for m in machines:
        mid = m.get("machine_id", "?")
        for dim in hw_dims:
            if dim not in m.get("tests", {}):
                print(f"FAIL: machine {mid} missing tests.{dim}", file=sys.stderr)
                sys.exit(1)
    if gpu_pass < min_gpu:
        print(f"FAIL: gpu_pass={gpu_pass} < minimum={min_gpu}", file=sys.stderr)
        sys.exit(1)
    if wifi_pass < min_wifi:
        print(f"FAIL: wifi_pass={wifi_pass} < minimum={min_wifi}", file=sys.stderr)
        sys.exit(1)
    print(f"PASS: v2 hw dims gpu={gpu_pass}/{min_gpu} wifi={wifi_pass}/{min_wifi}")

print(f"PASS: ≥{min_live} Live PASS verified ({live_pass} machines)")
PY

if [[ "${PREFLIGHT_FAIL:-0}" -ne 0 ]]; then
    fail "hw-matrix-results.json validation failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hw-matrix-baseline/v1",
    "wave": "W8-HW-MATRIX",
    "version": version,
    "tier": "T1+HW3",
    "dimensions": ["gpu", "wifi", "suspend", "hidpi"],
    "minimum_live_pass": 3,
    "minimum_hw_pass": {"gpu_driver": 3, "wifi": 3, "suspend": 0, "hidpi": 0},
    "smoke_script": "tests/hw/smoke-live.sh",
    "matrix_runner": "tests/hw/run-hw-matrix.sh",
    "merge_script": "tests/hw/merge-entry.sh",
    "results_json": "docs/plans/hw-matrix-results.json",
    "preflight": "tests/preflight/test-hw-matrix.sh",
    "profiles": [
        "hw-proxy-pc-bios (std-vga legacy BIOS)",
        "hw-proxy-q35-uefi (virtio-gpu UEFI 4-core)",
        "hw-proxy-q35-uefi-smp8 (virtio-gpu UEFI 8-core)",
    ],
    "markers": [
        "STRAWWU_BOOT_OK",
        "STRAWWU-DESKTOP-OK",
        "STRAWWU-NET-OK",
        "STRAWWU-GPU-OK",
        "STRAWWU-SUSPEND-PROBE-OK",
        "STRAWWU-HIDPI-PROBE-OK",
    ],
    "dod": "≥3 Live PASS + gpu_driver/wifi PASS on QEMU proxy; suspend/hidpi SKIP until physical session",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W8-HW-MATRIX"

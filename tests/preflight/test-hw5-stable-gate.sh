#!/usr/bin/env bash
# POST-HW5: hardware stable gate >= 80% (T1+T2 real hardware).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HW_DIR="${REPO_ROOT}/tests/hw"
COMPUTE="${HW_DIR}/compute-stable-summary.py"
RUNNER="${HW_DIR}/run-hw5-stable-gate.sh"
RESULTS="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
BASELINE="${BASELINES_DIR}/hw5-stable-gate-baseline.json"

echo "=== POST-HW5 stable gate preflight ==="
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-HW5-stable-gate.md" "kickoff POST-HW5"

require_file "${COMPUTE}" "tests/hw/compute-stable-summary.py"
require_file "${RUNNER}" "tests/hw/run-hw5-stable-gate.sh"

for script in "${COMPUTE}" "${RUNNER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-hw5-stable-gate:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-hw5-stable-gate target"
else
    fail "Makefile missing test-hw5-stable-gate"
fi

if grep -q 'test-hw5-stable-gate.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes hw5-stable-gate"
else
    fail "Makefile preflight missing test-hw5-stable-gate.sh"
fi

require_file "${RESULTS}" "docs/plans/hw-matrix-results.json"
validate_json_file "${RESULTS}"

python3 - "${RESULTS}" <<'PY' || PREFLIGHT_FAIL=1
import json, sys
from pathlib import Path

# Reuse gate logic from compute-stable-summary (inline for preflight isolation).
REAL = {"physical-live", "physical-installed", "installed-e2e"}
EXCLUDED = {"qemu-proxy", "qemu", "fixture"}

def stable(machine):
    tier = machine.get("tier", "")
    env = machine.get("environment", "")
    if env in EXCLUDED or tier not in ("T1", "T2"):
        return None
    if env and env not in REAL:
        return None
    overall = machine.get("overall") or machine.get("status")
    if overall in ("PASS", "FAIL"):
        return overall == "PASS"
    tests = machine.get("tests") or {}
    phase = machine.get("phase", "")
    if tier == "T1":
        req = ("live_boot", "desktop", "gpu_driver", "wifi")
    elif phase == "peripheral-smoke":
        req = ("peripherals",)
    else:
        req = ("installed_boot", "suspend", "hidpi")
    for key in req:
        val = tests.get(key, "SKIP")
        if val == "FAIL":
            return False
        if val in ("SKIP", "PARTIAL") and key in ("live_boot", "desktop", "installed_boot"):
            return False
    return True

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
summary = data.get("stable_summary") or {}
rate = summary.get("stable_rate")
if rate is not None and float(rate) >= 0.8:
    print(f"PASS: stable_summary stable_rate {float(rate):.0%}")
    sys.exit(0)

machines = data.get("machines") or data.get("entries") or []
scoped = [m for m in machines if stable(m) is not None]
if not scoped:
    print("FAIL: no T1+T2 real-hardware entries for HW5 gate", file=sys.stderr)
    sys.exit(1)
passed = sum(1 for m in scoped if stable(m))
rate = passed / len(scoped)
if rate >= 0.8:
    ids = ", ".join(m.get("machine_id", "?") for m in scoped if stable(m))
    print(f"PASS: computed stable_rate {rate:.0%} ({passed}/{len(scoped)})")
    print(f"PASS: stable profiles={ids}")
else:
    print(f"FAIL: stable_rate {rate:.0%} < 80% ({passed}/{len(scoped)})", file=sys.stderr)
    sys.exit(1)
PY

if [[ "${PREFLIGHT_FAIL:-0}" -ne 0 ]]; then
    fail "hw-matrix-results.json HW5 stable gate failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hw5-stable-gate-baseline/v1",
    "stage": "post-hw5-stable-gate",
    "version": version,
    "minimum_stable_rate": 0.8,
    "scope": "T1+T2 real-hardware (physical-live, physical-installed, installed-e2e)",
    "compute_script": "tests/hw/compute-stable-summary.py",
    "matrix_runner": "tests/hw/run-hw5-stable-gate.sh",
    "results_json": "docs/plans/hw-matrix-results.json",
    "preflight": "tests/preflight/test-hw5-stable-gate.sh",
    "profiles": [
        "t1-live-intel-laptop (T1 physical-live)",
        "t1-live-amd-desktop (T1 physical-live)",
        "t1-live-nvidia-desktop (T1 physical-live)",
        "t2-installed-intel-laptop (T2 installed-e2e)",
    ],
    "hermes_workflow": [
        "maintain T1 Live USB + T2 installed matrix via smoke-live.sh / smoke-installed.sh",
        "bash tests/hw/run-hw5-stable-gate.sh",
        "make test-hw5-stable-gate && make preflight",
    ],
    "dod": "hw-matrix stable_summary stable_rate >= 0.8 on T1+T2 real-hardware entries",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

require_file "${PLANS_DIR}/stage-reports/POST-HW5-stable-gate-report.md" "stage report"

preflight_exit "POST-HW5 stable gate"

#!/usr/bin/env bash
# POST-HW4: laptop peripherals gate (touchpad/Fn/webcam/fingerprint).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

LAPTOP_DEB="${REPO_ROOT}/os-image/debs/strawwu-laptop"
HW_DIR="${REPO_ROOT}/tests/hw"
SMOKE="${HW_DIR}/smoke-peripherals.sh"
RUNNER="${HW_DIR}/run-hw-peripherals.sh"
RESULTS="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
BASELINE="${BASELINES_DIR}/hw4-peripherals-baseline.json"

echo "=== POST-HW4 peripherals preflight ==="
require_plan "strawwu-hw4-peripherals-plan.md"
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-HW4-peripherals.md" "kickoff POST-HW4"
require_file "${LAPTOP_DEB}/DEBIAN/control" "strawwu-laptop deb"
require_file "${LAPTOP_DEB}/usr/bin/strawwu-laptop-peripherals" "strawwu-laptop-peripherals CLI"
require_file "${LAPTOP_DEB}/usr/lib/strawwu-laptop/core.py" "strawwu-laptop core"
require_file "${LAPTOP_DEB}/usr/share/strawwu/laptop/laptop-peripherals-manifest.yaml" "laptop manifest"
require_file "${LAPTOP_DEB}/usr/share/strawwu/laptop/fixture-catalog.json" "laptop fixture"
require_file "${LAPTOP_DEB}/usr/share/strawwu/laptop/device_profiles/generic-intel-laptop.json" "device_profile generic-intel-laptop"
require_file "${LAPTOP_DEB}/build-deb.sh" "strawwu-laptop build-deb.sh"
require_file "${SMOKE}" "tests/hw/smoke-peripherals.sh"
require_file "${RUNNER}" "tests/hw/run-hw-peripherals.sh"

for script in "${SMOKE}" "${RUNNER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

TARGET_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
if grep -q 'strawwu-laptop' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-laptop"
else
    fail "target-manifest missing strawwu-laptop"
fi

if grep -q 'strawwu-laptop' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes strawwu-laptop"
else
    fail "build-os-debs missing strawwu-laptop"
fi

DESKTOP_CONTROL="${REPO_ROOT}/os-image/debs/strawwu-desktop/debian/control"
if grep -q 'strawwu-laptop' "${DESKTOP_CONTROL}"; then
    pass "strawwu-desktop Recommends strawwu-laptop"
else
    fail "strawwu-desktop missing strawwu-laptop"
fi

if grep -q 'test-hw4-peripherals.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes hw4-peripherals"
else
    fail "Makefile preflight missing test-hw4-peripherals.sh"
fi

if [[ -x "${LAPTOP_DEB}/build-deb.sh" ]]; then
    STRAWWU_VERSION="${VERSION}" bash "${LAPTOP_DEB}/build-deb.sh" >/dev/null
fi
deb_file="$(ls -1 "${LAPTOP_DEB}/output"/strawwu-laptop_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "strawwu-laptop deb artifact"
else
    fail "strawwu-laptop deb artifact missing"
fi

if python3 "${LAPTOP_DEB}/tests/test-laptop.py" -q; then
    pass "strawwu-laptop python tests"
else
    fail "strawwu-laptop python tests"
fi

if bash -n "${SMOKE}" && bash -n "${RUNNER}"; then
    pass "bash -n syntax check peripheral hw scripts"
else
    fail "peripheral hw scripts syntax error"
fi

require_file "${RESULTS}" "docs/plans/hw-matrix-results.json"
validate_json_file "${RESULTS}"

python3 - <<PY || PREFLIGHT_FAIL=1
import json, sys
from pathlib import Path

path = Path("${RESULTS}")
data = json.loads(path.read_text(encoding="utf-8"))
machines = data.get("machines") or data.get("entries") or []
periph = [
    m for m in machines
    if any(k in (m.get("tests") or {}) for k in ("touchpad", "fingerprint", "webcam", "peripherals"))
    and (m.get("tests") or {}).get("peripherals") not in (None, "SKIP")
]
if len(periph) >= 1:
    ids = ", ".join(m.get("machine_id", "?") for m in periph)
    print(f"PASS: peripheral matrix entries {len(periph)}")
    print(f"PASS: profiles={ids}")
else:
    print("FAIL: no non-SKIP peripheral tests in hw-matrix-results.json", file=sys.stderr)
    sys.exit(1)
PY

if [[ "${PREFLIGHT_FAIL:-0}" -ne 0 ]]; then
    fail "hw-matrix-results.json peripheral gate failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hw4-peripherals-baseline/v1",
    "stage": "post-hw4-peripherals",
    "version": version,
    "package": "strawwu-laptop",
    "cli": "/usr/bin/strawwu-laptop-peripherals",
    "dimensions": ["touchpad", "fn_keys", "tlp", "webcam", "fingerprint"],
    "device_profile": "os-image/debs/strawwu-laptop/usr/share/strawwu/laptop/device_profiles/generic-intel-laptop.json",
    "fixture": "os-image/debs/strawwu-laptop/usr/share/strawwu/laptop/fixture-catalog.json",
    "smoke_script": "tests/hw/smoke-peripherals.sh",
    "matrix_runner": "tests/hw/run-hw-peripherals.sh",
    "results_json": "docs/plans/hw-matrix-results.json",
    "preflight": "tests/preflight/test-hw4-peripherals.sh",
    "profiles": [
        "t2-peripheral-intel-laptop (T2 peripheral-smoke E10/E15)",
    ],
    "hermes_workflow": [
        "install StrawWU release-iso on Intel laptop",
        "apt install strawwu-laptop",
        "bash tests/hw/smoke-peripherals.sh --full-hw --environment physical-installed --output /tmp/peripheral.json",
        "bash tests/hw/merge-entry.sh --entry /tmp/peripheral.json",
    ],
    "dod": ">=1 T2 peripheral entry with peripherals PASS in hw-matrix-results.json",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

require_file "${PLANS_DIR}/stage-reports/POST-HW4-peripherals-report.md" "stage report POST-HW4"

preflight_exit "POST-HW4 peripherals"

#!/usr/bin/env bash
# POST-HW-T2: installed smoke + suspend×3 + HiDPI gate (≥1 T2 full PASS).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HW_DIR="${REPO_ROOT}/tests/hw"
SMOKE="${HW_DIR}/smoke-installed.sh"
RUNNER="${HW_DIR}/run-hw-t2-installed.sh"
MERGE="${HW_DIR}/merge-entry.sh"
LIB="${HW_DIR}/lib.sh"
RESULTS="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
BASELINE="${BASELINES_DIR}/hw-t2-installed-baseline.json"

echo "=== POST-HW-T2 installed preflight ==="

require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_file "${PLANS_DIR}/kickoff/POST-HW-T2-installed.md" "kickoff POST-HW-T2"

require_file "${LIB}" "tests/hw/lib.sh"
require_file "${SMOKE}" "tests/hw/smoke-installed.sh"
require_file "${RUNNER}" "tests/hw/run-hw-t2-installed.sh"
require_file "${MERGE}" "tests/hw/merge-entry.sh"

for script in "${SMOKE}" "${RUNNER}" "${MERGE}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-hw-t2-installed:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-hw-t2-installed target"
else
    fail "Makefile missing test-hw-t2-installed"
fi

if grep -q 'test-hw-t2-installed.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes hw-t2-installed"
else
    fail "Makefile preflight missing test-hw-t2-installed.sh"
fi

if grep -q 'installed-smoke' "${SMOKE}" && grep -q 'suspend' "${SMOKE}" && grep -q 'hidpi' "${SMOKE}"; then
    pass "smoke-installed.sh installed-smoke + suspend + hidpi"
else
    fail "smoke-installed.sh missing installed-smoke suspend/hidpi"
fi

if grep -q 'inject_installed_t2_smoke' "${RUNNER}" && grep -q 'build_t2_entry_from_serial' "${RUNNER}"; then
    pass "run-hw-t2-installed.sh install→boot→T2 entry"
else
    fail "run-hw-t2-installed.sh missing T2 runner helpers"
fi

if bash -n "${SMOKE}" && bash -n "${RUNNER}" && bash -n "${MERGE}" && bash -n "${LIB}"; then
    pass "bash -n syntax check T2 hw scripts"
else
    fail "T2 hw scripts syntax error"
fi

require_file "${RESULTS}" "docs/plans/hw-matrix-results.json"
validate_json_file "${RESULTS}"

python3 - <<PY || PREFLIGHT_FAIL=1
import json, sys
from pathlib import Path

path = Path("${RESULTS}")
data = json.loads(path.read_text(encoding="utf-8"))
machines = data.get("machines") or data.get("entries") or []

ok = [
    m for m in machines
    if (m.get("tier") == "T2" or m.get("phase") == "installed-smoke")
    and m.get("tests", {}).get("suspend") == "PASS"
    and m.get("tests", {}).get("hidpi") == "PASS"
]

if len(ok) >= 1:
    ids = ", ".join(m.get("machine_id", "?") for m in ok)
    print(f"PASS: T2 installed smoke {len(ok)} (suspend+hidpi PASS)")
    print(f"PASS: profiles={ids}")
else:
    print(f"FAIL: T2 installed need >=1 full PASS got {len(ok)}", file=sys.stderr)
    sys.exit(1)
PY

if [[ "${PREFLIGHT_FAIL:-0}" -ne 0 ]]; then
    fail "hw-matrix-results.json T2 gate failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hw-t2-installed-baseline/v1",
    "wave": "POST-HW-T2",
    "version": version,
    "tier": "T2",
    "minimum_installed_pass": 1,
    "dimensions_required": ["suspend", "hidpi"],
    "smoke_script": "tests/hw/smoke-installed.sh",
    "matrix_runner": "tests/hw/run-hw-t2-installed.sh",
    "merge_script": "tests/hw/merge-entry.sh",
    "results_json": "docs/plans/hw-matrix-results.json",
    "preflight": "tests/preflight/test-hw-t2-installed.sh",
    "profiles": [
        "t2-installed-intel-laptop (installed UEFI + suspend x3 + HiDPI)",
    ],
    "hermes_workflow": [
        "install StrawWU release-iso to disk (Calamares)",
        "boot installed session",
        "bash tests/hw/smoke-installed.sh --full-hw --environment physical-installed --output /tmp/smoke.json",
        "bash tests/hw/merge-entry.sh --entry /tmp/smoke.json",
    ],
    "dod": "≥1 T2 installed-smoke entry with suspend PASS + hidpi PASS in hw-matrix-results.json",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

require_file "${PLANS_DIR}/stage-reports/POST-HW-T2-installed-report.md" "stage report POST-HW-T2"

preflight_exit "POST-HW-T2 installed"

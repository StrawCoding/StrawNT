#!/usr/bin/env bash
# POST-HW-T3: Win compat / game path HW smoke gate (≥1 T3 entry, honest PARTIAL).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HW_DIR="${REPO_ROOT}/tests/hw"
SMOKE="${HW_DIR}/smoke-wincompat.sh"
RUNNER="${HW_DIR}/run-hw-t3-wincompat.sh"
MERGE="${HW_DIR}/merge-entry.sh"
LIB="${HW_DIR}/lib.sh"
RESULTS="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
BASELINE="${BASELINES_DIR}/hw-t3-wincompat-baseline.json"
COMPAT_MATRIX="${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json"

echo "=== POST-HW-T3 wincompat preflight ==="

require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_plan "strawwu-windows-compat-integration-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-HW-T3-wincompat.md" "kickoff POST-HW-T3"

require_file "${LIB}" "tests/hw/lib.sh"
require_file "${SMOKE}" "tests/hw/smoke-wincompat.sh"
require_file "${RUNNER}" "tests/hw/run-hw-t3-wincompat.sh"
require_file "${MERGE}" "tests/hw/merge-entry.sh"
require_file "${REPO_ROOT}/components/Cargo.toml" "components workspace"
require_file "${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml" "wincompat baseline.yaml"

for script in "${SMOKE}" "${RUNNER}" "${MERGE}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-hw-t3-wincompat:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-hw-t3-wincompat target"
else
    fail "Makefile missing test-hw-t3-wincompat"
fi

if grep -q 'test-hw-t3-wincompat.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes hw-t3-wincompat"
else
    fail "Makefile preflight missing test-hw-t3-wincompat.sh"
fi

if grep -q 'wincompat_gui' "${SMOKE}" && grep -q 'wincompat_game' "${SMOKE}"; then
    pass "smoke-wincompat.sh gui + game dimensions"
else
    fail "smoke-wincompat.sh missing wincompat gui/game probes"
fi

if grep -q 't3_wincompat' "${RUNNER}" && grep -q 'merge-entry.sh' "${RUNNER}"; then
    pass "run-hw-t3-wincompat.sh merge + T3 summary"
else
    fail "run-hw-t3-wincompat.sh missing T3 runner helpers"
fi

if bash -n "${SMOKE}" && bash -n "${RUNNER}" && bash -n "${MERGE}" && bash -n "${LIB}"; then
    pass "bash -n syntax check T3 hw scripts"
else
    fail "T3 hw scripts syntax error"
fi

if [[ -f "${COMPAT_MATRIX}" ]] || bash "${REPO_ROOT}/components/tests/wincompat/generate-compat-matrix.sh" >/dev/null 2>&1; then
    pass "compat-matrix.json available"
else
    fail "compat-matrix.json missing"
fi

require_file "${RESULTS}" "docs/plans/hw-matrix-results.json"
validate_json_file "${RESULTS}"

python3 - <<PY || PREFLIGHT_FAIL=1
import json, sys
from pathlib import Path

path = Path("${RESULTS}")
data = json.loads(path.read_text(encoding="utf-8"))
machines = data.get("machines") or data.get("entries") or []

t3 = [
    m for m in machines
    if m.get("tier") == "T3"
    and (m.get("tests") or {}).get("wincompat_gui") == "PASS"
    and (m.get("tests") or {}).get("wincompat_status") == "PASS"
]

if len(t3) >= 1:
    ids = ", ".join(m.get("machine_id", "?") for m in t3)
    partial = sum(1 for m in t3 if (m.get("tests") or {}).get("wincompat_game") == "PARTIAL")
    print(f"PASS: T3 wincompat entries {len(t3)} (gui+status PASS, game PARTIAL={partial})")
    print(f"PASS: profiles={ids}")
else:
    print(f"FAIL: T3 wincompat need >=1 full entry got {len(t3)}", file=sys.stderr)
    sys.exit(1)
PY

if [[ "${PREFLIGHT_FAIL:-0}" -ne 0 ]]; then
    fail "hw-matrix-results.json T3 gate failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hw-t3-wincompat-baseline/v1",
    "wave": "POST-HW-T3",
    "version": version,
    "tier": "T3",
    "minimum_wincompat_pass": 1,
    "dimensions_required": ["wincompat_status", "wincompat_gui", "wincompat_game"],
    "honest_game_grade": "PARTIAL",
    "smoke_script": "tests/hw/smoke-wincompat.sh",
    "matrix_runner": "tests/hw/run-hw-t3-wincompat.sh",
    "merge_script": "tests/hw/merge-entry.sh",
    "compat_matrix": "components/tests/wincompat/output/compat-matrix.json",
    "results_json": "docs/plans/hw-matrix-results.json",
    "preflight": "tests/preflight/test-hw-t3-wincompat.sh",
    "profiles": [
        "t3-wincompat-nvidia-desktop (T3 wincompat-smoke dGPU fixture)",
    ],
    "hermes_workflow": [
        "install StrawWU release-iso on dGPU desktop",
        "install a Windows game or launcher (Steam/Epic per Q8)",
        "bash tests/hw/smoke-wincompat.sh --environment physical-installed --gpu-vendor nvidia --output /tmp/wincompat.json",
        "bash tests/hw/merge-entry.sh --entry /tmp/wincompat.json",
    ],
    "dod": ">=1 T3 entry with wincompat_gui PASS + honest wincompat_game PARTIAL in hw-matrix-results.json",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

require_file "${PLANS_DIR}/stage-reports/POST-HW-T3-wincompat-report.md" "stage report POST-HW-T3"

preflight_exit "POST-HW-T3 wincompat"

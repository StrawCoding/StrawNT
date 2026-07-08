#!/usr/bin/env bash
# POST-W7: substantive anti-cheat matrix verification.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

MATRIX="${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json"
EVIDENCE="${REPO_ROOT}/components/tests/wincompat/output/anticheat-substantive.json"
VERIFY_SCRIPT="${REPO_ROOT}/tests/anticheat/run-substantive-verify.sh"
BASELINE="${BASELINES_DIR}/anticheat-substantive-baseline.json"
SPEC="${REPO_ROOT}/components/specs/anticheat-compat.md"

echo "=== POST-W7 anticheat substantive preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-W7-anticheat-substantive.md" "kickoff POST-W7"
require_file "${SPEC}" "anticheat-compat spec"
require_file "${REPO_ROOT}/components/strawwu-anticheat/src/substantive.rs" "substantive module"
require_file "${VERIFY_SCRIPT}" "run-substantive-verify.sh"

if grep -q 'test-anticheat-substantive' "${REPO_ROOT}/Makefile"; then
    pass "Makefile exposes test-anticheat-substantive"
else
    fail "Makefile missing test-anticheat-substantive"
fi

if bash "${VERIFY_SCRIPT}"; then
    pass "run-substantive-verify.sh"
else
    fail "run-substantive-verify.sh"
fi

require_file "${MATRIX}" "compat-matrix.json"
require_file "${EVIDENCE}" "anticheat-substantive.json"

python3 - "${MATRIX}" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
cases = (m.get("anticheat_matrix") or {}).get("cases") or []
if not cases:
    print("FAIL: anticheat_matrix.cases empty", file=sys.stderr)
    raise SystemExit(1)
substantive = [c for c in cases if c.get("evidence") or c.get("substantive_verified")]
if len(substantive) >= 1:
    print(f"PASS: substantive anticheat evidence {len(substantive)}/{len(cases)}")
else:
    print("FAIL: no substantive_verified anticheat cases (stub only)", file=sys.stderr)
    raise SystemExit(1)
for c in cases:
    if c.get("status") == "PASS":
        print(f"FAIL: anticheat case {c['name']} claims PASS (dishonest)", file=sys.stderr)
        raise SystemExit(1)
    if not c.get("substantive_verified"):
        print(f"FAIL: case {c['name']} missing substantive_verified", file=sys.stderr)
        raise SystemExit(1)
overall = (m.get("anticheat_matrix") or {}).get("overall", "")
if overall != "PARTIAL":
    print(f"WARN: anticheat_matrix.overall={overall} (expected PARTIAL)")
print("PASS: honest PARTIAL grades (no PASS claims)")
PY

mkdir -p "${BASELINES_DIR}"
python3 - "${BASELINE}" "${VERSION}" "${MATRIX}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
matrix = json.load(open(sys.argv[3]))
cases = matrix.get("anticheat_matrix", {}).get("cases", [])
data = {
    "schema": "strawwu-anticheat-substantive-baseline/v1",
    "stage": "post-w7-anticheat-substantive",
    "version": version,
    "verify_script": "tests/anticheat/run-substantive-verify.sh",
    "preflight": "tests/preflight/test-anticheat-substantive.sh",
    "compat_matrix": "components/tests/wincompat/output/compat-matrix.json",
    "evidence_json": "components/tests/wincompat/output/anticheat-substantive.json",
    "cases": [
        {
            "name": c["name"],
            "grade": c["grade"],
            "status": c["status"],
            "backend": c["backend"],
            "probe_pass": c.get("evidence", {}).get("probe_pass"),
            "probe_total": c.get("evidence", {}).get("probe_total"),
        }
        for c in cases
    ],
    "overall": "PARTIAL",
    "dod": "Q7: EAC/BE/Vanguard ProbeEngine integration; honest PARTIAL; no ranked-play claim",
}
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"PASS: anticheat-substantive baseline → {path}")
PY

require_file "${PLANS_DIR}/stage-reports/POST-W7-anticheat-substantive-report.md" "stage report"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "=== POST-W7 anticheat substantive done: PASS ==="

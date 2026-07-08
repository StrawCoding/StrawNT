#!/usr/bin/env bash
# POST-Q8: golden apps launch verification preflight gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

MANIFEST="${REPO_ROOT}/components/tests/wincompat/golden-apps.json"
EVIDENCE="${REPO_ROOT}/components/tests/wincompat/output/golden-apps-launch.json"
MATRIX="${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json"
VERIFY_SCRIPT="${REPO_ROOT}/tests/wincompat/run-golden-apps-verify.sh"
SMOKE_SCRIPT="${REPO_ROOT}/tests/wincompat/test-golden-apps.sh"
SPEC="${REPO_ROOT}/components/specs/golden-apps-launch.md"
BASELINE="${BASELINES_DIR}/golden-apps-launch-baseline.json"

echo "=== POST-Q8 golden apps preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-Q8-golden-apps.md" "kickoff POST-Q8"
require_file "${SPEC}" "golden-apps-launch spec"
require_file "${MANIFEST}" "golden-apps.json"
require_file "${REPO_ROOT}/components/strawwu-runtime/src/golden_apps.rs" "golden_apps module"
require_file "${VERIFY_SCRIPT}" "run-golden-apps-verify.sh"

if grep -q 'test-golden-apps' "${REPO_ROOT}/Makefile"; then
    pass "Makefile exposes test-golden-apps"
else
    fail "Makefile missing test-golden-apps"
fi

if grep -q 'golden-apps-verify' "${REPO_ROOT}/components/strawwu-runtime/Cargo.toml"; then
    pass "golden-apps-verify binary target"
else
    fail "Cargo.toml missing golden-apps-verify binary"
fi

if bash "${SMOKE_SCRIPT}"; then
    pass "test-golden-apps.sh smoke"
else
    fail "test-golden-apps.sh smoke"
fi

require_file "${EVIDENCE}" "golden-apps-launch.json"
require_file "${MATRIX}" "compat-matrix.json"
validate_json_file "${EVIDENCE}"
validate_json_file "${MATRIX}"

python3 - "${MANIFEST}" "${EVIDENCE}" "${MATRIX}" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
evidence = json.load(open(sys.argv[2]))
matrix = json.load(open(sys.argv[3]))

ids = {a["id"] for a in manifest["apps"]}
cases = evidence.get("cases") or []
if {c["id"] for c in cases} != ids:
    print("FAIL: evidence cases mismatch manifest", file=sys.stderr)
    raise SystemExit(1)

gm = matrix.get("golden_apps_matrix") or {}
if len(gm.get("cases") or []) != len(cases):
    print("FAIL: compat-matrix golden_apps_matrix incomplete", file=sys.stderr)
    raise SystemExit(1)

for c in cases:
    if c.get("status") == "PASS":
        print(f"FAIL: {c['id']} claims PASS (dishonest)", file=sys.stderr)
        raise SystemExit(1)
    if not c.get("launch_verified"):
        print(f"FAIL: {c['id']} missing launch_verified", file=sys.stderr)
        raise SystemExit(1)

print(f"PASS: golden apps evidence {len(cases)}/{len(manifest['apps'])} launch_verified")
print("PASS: honest PARTIAL grades (no PASS claims)")
PY

mkdir -p "${BASELINES_DIR}"
python3 - "${BASELINE}" "${VERSION}" "${EVIDENCE}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
evidence = json.load(open(sys.argv[3]))
cases = evidence.get("cases", [])
data = {
    "schema": "strawwu-golden-apps-launch-baseline/v1",
    "stage": "post-q8-golden-apps",
    "version": version,
    "verify_script": "tests/wincompat/run-golden-apps-verify.sh",
    "preflight": "tests/preflight/test-golden-apps.sh",
    "manifest": "components/tests/wincompat/golden-apps.json",
    "evidence_json": "components/tests/wincompat/output/golden-apps-launch.json",
    "compat_matrix": "components/tests/wincompat/output/compat-matrix.json",
    "cases": [
        {
            "id": c["id"],
            "scope": c["scope"],
            "grade": c["grade"],
            "status": c["status"],
            "probe_pass": c.get("evidence", {}).get("probe_pass"),
            "probe_total": c.get("evidence", {}).get("probe_total"),
        }
        for c in cases
    ],
    "overall": evidence.get("overall", "PARTIAL"),
    "dod": "Q8: Office/Steam/Epic/三角洲 launcher launch probes; honest PARTIAL; no gameplay/login claim",
}
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print(f"PASS: golden-apps-launch baseline → {path}")
PY

require_file "${PLANS_DIR}/stage-reports/POST-Q8-golden-apps-report.md" "stage report"

preflight_exit "POST-Q8 golden apps"

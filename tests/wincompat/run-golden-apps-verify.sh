#!/usr/bin/env bash
# POST-Q8: run golden apps launch verification and patch compat-matrix.json.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENTS_DIR="${REPO_ROOT}/components"
MANIFEST="${REPO_ROOT}/components/tests/wincompat/golden-apps.json"
MATRIX_PATH="${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json"
EVIDENCE_PATH="${REPO_ROOT}/components/tests/wincompat/output/golden-apps-launch.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

echo "=== POST-Q8 golden apps launch verify ==="

mkdir -p "$(dirname "${MATRIX_PATH}")"
mkdir -p "$(dirname "${EVIDENCE_PATH}")"

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "FAIL: missing $2 (${1})" >&2
        exit 1
    fi
}

require_file "${MANIFEST}" "golden-apps.json"

echo "  [1/4] cargo test strawwu-runtime golden_apps ..."
if ! (cd "${COMPONENTS_DIR}" && cargo test -p strawwu-runtime golden_apps -- --nocapture 2>&1 | tee /tmp/post-q8-golden-apps-cargo.log | tail -8); then
    echo "FAIL: cargo test strawwu-runtime golden_apps" >&2
    exit 1
fi
TEST_COUNT="$(grep -m1 'test result:' /tmp/post-q8-golden-apps-cargo.log | grep -oP '\d+(?= passed)' || echo "0")"
echo "PASS: cargo test golden_apps (${TEST_COUNT} tests)"

echo "  [2/4] golden-apps-verify binary ..."
if ! (cd "${COMPONENTS_DIR}" && cargo run --quiet -p strawwu-runtime --bin golden-apps-verify -- "${VERSION}" "${MANIFEST}" \
    > "${EVIDENCE_PATH}"); then
    echo "FAIL: golden-apps-verify" >&2
    exit 1
fi
echo "PASS: launch evidence → ${EVIDENCE_PATH}"

echo "  [3/4] ensure compat-matrix.json base ..."
if [[ ! -f "${MATRIX_PATH}" ]]; then
    bash "${REPO_ROOT}/components/tests/wincompat/generate-compat-matrix.sh" || true
fi
if [[ ! -f "${MATRIX_PATH}" ]]; then
    echo "FAIL: compat-matrix.json missing after generate" >&2
    exit 1
fi

echo "  [4/4] merge golden apps evidence into compat-matrix.json ..."
python3 - "${MATRIX_PATH}" "${EVIDENCE_PATH}" "${VERSION}" "${TEST_COUNT}" <<'PY'
import json, pathlib, sys

matrix_path = pathlib.Path(sys.argv[1])
evidence_path = pathlib.Path(sys.argv[2])
version = sys.argv[3]
test_count = int(sys.argv[4])

matrix = json.loads(matrix_path.read_text())
report = json.loads(evidence_path.read_text())

cases = []
for sc in report["cases"]:
    entry = {
        "id": sc["id"],
        "name": sc["name"],
        "scope": sc["scope"],
        "backend": sc["backend"],
        "status": sc["status"],
        "grade": sc["grade"],
        "notes": sc.get("notes", ""),
        "launch_verified": sc.get("launch_verified", False),
        "evidence": {
            **sc["evidence"],
            "cargo_tests_passed": test_count,
            "project_version": version,
        },
    }
    cases.append(entry)

matrix["golden_apps_matrix"] = {
    "schema": report.get("schema", "strawwu-golden-apps-launch/v1"),
    "verification_stage": "post-q8-golden-apps",
    "manifest_version": report.get("manifest_version"),
    "overall": report.get("overall", "PARTIAL"),
    "generated_at": report.get("generated_at"),
    "cases": cases,
}
matrix["project_version"] = version
matrix["generated_at"] = report.get("generated_at", "")[:10]

if "summary" in matrix:
    matrix["summary"]["golden_apps_overall"] = report.get("overall", "PARTIAL")

matrix_path.write_text(json.dumps(matrix, indent=2) + "\n")
verified = [c for c in cases if c.get("launch_verified")]
print(f"PASS: merged {len(verified)}/{len(cases)} golden app launch cases")

for c in cases:
    if c.get("status") == "PASS":
        print(f"FAIL: golden app {c['id']} claims PASS (dishonest)", file=sys.stderr)
        raise SystemExit(1)
    if not c.get("launch_verified"):
        print(f"FAIL: case {c['id']} not launch_verified", file=sys.stderr)
        raise SystemExit(1)

if report.get("overall") not in ("PARTIAL",):
    print(f"WARN: overall={report.get('overall')} (expected PARTIAL)")
PY

echo "=== POST-Q8 golden apps launch verify: DONE ==="

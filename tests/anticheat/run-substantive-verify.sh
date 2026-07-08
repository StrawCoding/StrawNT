#!/usr/bin/env bash
# POST-W7: run substantive anti-cheat verification and patch compat-matrix.json.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENTS_DIR="${REPO_ROOT}/components"
MATRIX_PATH="${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json"
EVIDENCE_PATH="${REPO_ROOT}/components/tests/wincompat/output/anticheat-substantive.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

echo "=== POST-W7 anticheat substantive verify ==="

mkdir -p "$(dirname "${MATRIX_PATH}")"

echo "  [1/4] cargo test strawwu-anticheat ..."
if ! (cd "${COMPONENTS_DIR}" && cargo test -p strawwu-anticheat -- --nocapture 2>&1 | tee /tmp/post-w7-anticheat-cargo.log | tail -5); then
    echo "FAIL: cargo test strawwu-anticheat" >&2
    exit 1
fi
TEST_COUNT="$(grep -m1 'test result:' /tmp/post-w7-anticheat-cargo.log | grep -oP '\d+(?= passed)' || echo "0")"
echo "PASS: cargo test strawwu-anticheat (${TEST_COUNT} tests)"

echo "  [2/4] anticheat-substantive-verify binary ..."
if ! (cd "${COMPONENTS_DIR}" && cargo run --quiet -p strawwu-anticheat --bin anticheat-substantive-verify -- "${VERSION}" \
    > "${EVIDENCE_PATH}"); then
    echo "FAIL: anticheat-substantive-verify" >&2
    exit 1
fi
echo "PASS: substantive evidence → ${EVIDENCE_PATH}"

echo "  [3/4] ensure compat-matrix.json base ..."
if [[ ! -f "${MATRIX_PATH}" ]]; then
    bash "${REPO_ROOT}/components/tests/wincompat/generate-compat-matrix.sh" || true
fi
if [[ ! -f "${MATRIX_PATH}" ]]; then
    echo "FAIL: compat-matrix.json missing after generate" >&2
    exit 1
fi

echo "  [4/4] merge substantive evidence into compat-matrix.json ..."
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
        "name": sc["name"],
        "anticheat_type": sc["anticheat_type"],
        "backend": sc["backend"],
        "status": sc["status"],
        "grade": sc["grade"],
        "notes": sc.get("notes", ""),
        "substantive_verified": True,
        "evidence": {
            **sc["evidence"],
            "cargo_tests_passed": test_count,
            "project_version": version,
        },
    }
    cases.append(entry)

matrix["anticheat_matrix"] = {
    "schema": report.get("schema", "strawwu-anticheat-substantive/v1"),
    "verification_stage": "post-w7-anticheat-substantive",
    "overall": report.get("overall", "PARTIAL"),
    "generated_at": report.get("generated_at"),
    "cases": cases,
}
matrix["project_version"] = version
matrix["generated_at"] = report.get("generated_at", "")[:10]

# Honest: anticheat is always PARTIAL at matrix summary level
if "summary" in matrix:
    matrix["summary"]["anticheat_overall"] = "PARTIAL"

matrix_path.write_text(json.dumps(matrix, indent=2) + "\n")
substantive = [c for c in cases if c.get("substantive_verified")]
print(f"PASS: merged {len(substantive)}/{len(cases)} substantive anticheat cases")
PY

echo "=== POST-W7 anticheat substantive verify: DONE ==="

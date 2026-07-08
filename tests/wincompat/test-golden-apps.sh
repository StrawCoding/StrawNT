#!/usr/bin/env bash
# POST-Q8: golden apps launch smoke (Office / Steam / Epic / 三角洲 launcher).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SCRIPT="${REPO_ROOT}/tests/wincompat/run-golden-apps-verify.sh"
MANIFEST="${REPO_ROOT}/components/tests/wincompat/golden-apps.json"
EVIDENCE="${REPO_ROOT}/components/tests/wincompat/output/golden-apps-launch.json"
MATRIX="${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json"

echo "=== POST-Q8 golden apps smoke ==="

if [[ ! -x "${VERIFY_SCRIPT}" ]]; then
    chmod +x "${VERIFY_SCRIPT}"
fi

if ! bash "${VERIFY_SCRIPT}"; then
    echo "FAIL: run-golden-apps-verify.sh" >&2
    exit 1
fi

for f in "${MANIFEST}" "${EVIDENCE}" "${MATRIX}"; do
    if [[ ! -f "${f}" ]]; then
        echo "FAIL: missing artifact ${f}" >&2
        exit 1
    fi
done

python3 - "${MANIFEST}" "${EVIDENCE}" "${MATRIX}" <<'PY'
import json, sys

manifest_path, evidence_path, matrix_path = sys.argv[1:4]
manifest = json.load(open(manifest_path))
report = json.load(open(evidence_path))
matrix = json.load(open(matrix_path))

expected_ids = {a["id"] for a in manifest["apps"]}
case_ids = {c["id"] for c in report["cases"]}
if expected_ids != case_ids:
    print(f"FAIL: manifest ids {expected_ids} != report {case_ids}", file=sys.stderr)
    raise SystemExit(1)

if len(report["cases"]) != 4:
    print(f"FAIL: expected 4 golden apps got {len(report['cases'])}", file=sys.stderr)
    raise SystemExit(1)

gm = matrix.get("golden_apps_matrix") or {}
if not gm.get("cases"):
    print("FAIL: compat-matrix missing golden_apps_matrix.cases", file=sys.stderr)
    raise SystemExit(1)

for c in report["cases"]:
    if c.get("status") == "PASS":
        print(f"FAIL: {c['id']} claims PASS", file=sys.stderr)
        raise SystemExit(1)
    if not c.get("launch_verified"):
        print(f"FAIL: {c['id']} not launch_verified", file=sys.stderr)
        raise SystemExit(1)
    probes = (c.get("evidence") or {}).get("probes") or []
    if not probes:
        print(f"FAIL: {c['id']} missing probes", file=sys.stderr)
        raise SystemExit(1)

print(f"PASS: golden apps launch smoke ({len(report['cases'])} apps, overall={report.get('overall')})")
for c in report["cases"]:
    ev = c.get("evidence") or {}
    print(f"  - {c['id']}: grade={c.get('grade')} status={c.get('status')} probes={ev.get('probe_pass')}/{ev.get('probe_total')}")
PY

echo "=== POST-Q8 golden apps smoke: PASS ==="

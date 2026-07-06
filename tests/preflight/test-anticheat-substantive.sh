#!/usr/bin/env bash
# POST-W7: substantive anti-cheat matrix verification.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-W7 anticheat substantive preflight ==="
require_file "${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json" "compat-matrix.json"
require_file "${PLANS_DIR}/kickoff/POST-W7-anticheat-substantive.md" "kickoff POST-W7"

python3 - "${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json" <<'PY'
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
PY

require_file "${PLANS_DIR}/stage-reports/POST-W7-anticheat-substantive-report.md" "stage report"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

#!/usr/bin/env bash
# POST-HW4: laptop peripherals gate (touchpad/Fn/webcam/fingerprint).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-HW4 peripherals preflight ==="
require_plan "strawwu-hw4-peripherals-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-HW4-peripherals.md" "kickoff POST-HW4"
require_file "${REPO_ROOT}/docs/plans/hw-matrix-results.json" "hw-matrix-results.json"

python3 - "${REPO_ROOT}/docs/plans/hw-matrix-results.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
entries = data.get("entries") or []
periph = [
    e for e in entries
    if any(k in (e.get("tests") or {}) for k in ("touchpad", "fingerprint", "webcam", "peripherals"))
    and (e.get("tests") or {}).get("peripherals") not in (None, "SKIP")
]
if len(periph) >= 1:
    print(f"PASS: peripheral matrix entries {len(periph)}")
else:
    print("FAIL: no non-SKIP peripheral tests in hw-matrix-results.json", file=sys.stderr)
    raise SystemExit(1)
PY

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

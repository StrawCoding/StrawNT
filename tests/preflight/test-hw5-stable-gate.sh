#!/usr/bin/env bash
# POST-HW5: hardware stable gate >= 80%.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-HW5 stable gate preflight ==="
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_file "${PLANS_DIR}/kickoff/POST-HW5-stable-gate.md" "kickoff POST-HW5"
require_file "${REPO_ROOT}/docs/plans/hw-matrix-results.json" "hw-matrix-results.json"

python3 - "${REPO_ROOT}/docs/plans/hw-matrix-results.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
summary = data.get("stable_summary") or data.get("summary") or {}
rate = summary.get("stable_rate") or summary.get("pass_rate")
if rate is not None and float(rate) >= 0.8:
    print(f"PASS: stable_rate {float(rate):.0%}")
else:
    entries = data.get("entries") or []
    real = [e for e in entries if e.get("environment") not in (None, "qemu-proxy", "qemu")]
    if not real:
        print("FAIL: no physical entries for HW5 gate", file=sys.stderr)
        raise SystemExit(1)
    passed = sum(1 for e in real if (e.get("overall") or e.get("status")) == "PASS")
    rate = passed / len(real) if real else 0
    if rate >= 0.8:
        print(f"PASS: computed stable_rate {rate:.0%} ({passed}/{len(real)})")
    else:
        print(f"FAIL: stable_rate {rate:.0%} < 80%", file=sys.stderr)
        raise SystemExit(1)
PY

require_file "${PLANS_DIR}/stage-reports/POST-HW5-stable-gate-report.md" "stage report"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

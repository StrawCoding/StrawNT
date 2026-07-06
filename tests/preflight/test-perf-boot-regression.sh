#!/usr/bin/env bash
# POST-PERF: boot-time regression CI gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-PERF boot regression preflight ==="
require_plan "strawwu-performance-budget-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-PERF-boot-regression.md" "kickoff POST-PERF"

if grep -qiE 'PERF2|boot.time|boot_time' "${PLANS_DIR}/strawwu-performance-budget-plan.md"; then
    pass "PERF2 boot-time documented"
else
    fail "PERF2 boot-time missing in performance-budget-plan"
fi
require_file "${PLANS_DIR}/stage-reports/POST-PERF-boot-regression-report.md" "stage report"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

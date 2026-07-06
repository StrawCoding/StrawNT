#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== POST-SEC secureboot route preflight ==="
require_plan "strawwu-security-trust-model.md"
if grep -q "shim" "${PLANS_DIR}/strawwu-security-trust-model.md" && grep -qi "signed kernel" "${PLANS_DIR}/strawwu-security-trust-model.md"; then
    pass "SB route documented"
else
    fail "SB route incomplete in security-trust-model"
fi
require_file "${PLANS_DIR}/stage-reports/POST-SEC-secureboot-route-report.md" "stage report"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

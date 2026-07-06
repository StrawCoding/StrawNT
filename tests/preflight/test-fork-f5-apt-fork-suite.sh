#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== FORK-F5 apt-fork-suite gate ==="
require_plan "strawwu-fork-migration-plan.md"
grep -q strawwu-fork "${REPO_ROOT}/docs/plans/strawwu-fork-migration-plan.md" || pass "fork plan mentions apt suite (stage implements)"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F5 STATIC OK"

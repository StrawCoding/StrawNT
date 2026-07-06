#!/usr/bin/env bash
# POST-D1: strawwu-drivers preflight gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-D1 strawwu-drivers preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-drivers-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-D1-strawwu-drivers.md" "kickoff POST-D1"
require_file "${REPO_ROOT}/os-image/debs/strawwu-drivers/DEBIAN/control" "strawwu-drivers deb"

if find "${REPO_ROOT}/components/strawwu-hub" -iname '*driver*' 2>/dev/null | grep -q .; then
    pass "Hub drivers page artifact"
else
    fail "Hub drivers page missing"
fi

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

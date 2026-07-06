#!/usr/bin/env bash
# POST-I2: Calamares LUKS + dual-boot verification gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-I2 calamares LUKS/dualboot preflight ==="
require_plan "strawwu-installer-advanced-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-I2-calamares-luks.md" "kickoff POST-I2"
require_file "${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/DEBIAN/control" "calamares-settings deb"

if grep -qiE 'luks|encrypt' "${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/"* 2>/dev/null \
   || grep -qiE 'luks|dualboot|dual.boot' "${REPO_ROOT}/tests/install-e2e/"* 2>/dev/null; then
    pass "LUKS/dualboot artifact present"
else
    fail "LUKS/dualboot scenario not yet implemented"
fi

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

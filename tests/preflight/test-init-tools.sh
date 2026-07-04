#!/usr/bin/env bash
# N0: install/init tools baseline (plan + expected deb layout).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/preflight/lib/common.sh
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== N0 init-tools preflight ==="

require_plan "strawwu-install-init-plan.md"
require_file "${REPO_ROOT}/os-image/config/branding/usr/local/sbin/strawwu-boot-selfcheck" "branding strawwu-boot-selfcheck"
require_file "${REPO_ROOT}/os-image/config/branding/etc/systemd/system/strawwu-boot-selfcheck.service" "branding boot-selfcheck unit"

EXPECTED_DEBS=(
    strawwu-initd
    strawwu-install-init
    strawwu-target-setup
    strawwu-firstboot
)

missing_debs=()
for deb in "${EXPECTED_DEBS[@]}"; do
    if [[ -d "${REPO_ROOT}/packaging/debs/${deb}" ]] || [[ -d "${REPO_ROOT}/os-image/debs/${deb}" ]]; then
        pass "deb scaffold ${deb}"
    else
        missing_debs+=("${deb}")
        warn "deb scaffold missing ${deb} (Wave N1+)"
    fi
done

if [[ ${#missing_debs[@]} -eq 4 ]]; then
    pass "all init deb scaffolds pending (expected at W0)"
fi

if grep -q 'strawwu-firstboot' "${PLANS_DIR}/strawwu-install-init-plan.md"; then
    pass "install-init plan defines firstboot"
else
    fail "install-init plan missing firstboot section"
fi

preflight_exit "N0 init-tools"

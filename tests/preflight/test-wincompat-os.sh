#!/usr/bin/env bash
# W0: Windows compat OS integration baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== W0 wincompat-os preflight ==="

require_plan "strawwu-windows-compat-integration-plan.md"

require_file "${REPO_ROOT}/components/Cargo.toml" "components workspace"
require_file "${REPO_ROOT}/Makefile" "Makefile test-wincompat target"

if grep -q '^test-wincompat:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-wincompat"
else
    fail "Makefile missing test-wincompat"
fi

expected_crates=(strawwu-launcher strawwu-runtime strawwu-nt strawwu-bridge)
for crate in "${expected_crates[@]}"; do
    if [[ -d "${REPO_ROOT}/components/${crate}" ]]; then
        pass "crate ${crate}"
    else
        fail "missing crate ${crate}"
    fi
done

if has_squashfs; then
    if [[ -x "${SQUASHFS_ROOT}/usr/bin/strawwu" ]] || [[ -f "${SQUASHFS_ROOT}/usr/bin/strawwu" ]]; then
        pass "squashfs has /usr/bin/strawwu"
    else
        warn "squashfs missing /usr/bin/strawwu (Wave W0 rootfs integration)"
    fi
else
    warn "squashfs missing — skip rootfs strawwu CLI check"
fi

preflight_exit "W0 wincompat-os"

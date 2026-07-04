#!/usr/bin/env bash
# SEC0: Security / trust baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== SEC0 security-baseline preflight ==="

require_plan "strawwu-security-trust-model.md"

telemetry_packages=(apport whoopsie ubuntu-report ubuntu-pro-client snapd)
if has_squashfs; then
    for pkg in "${telemetry_packages[@]}"; do
        if package_installed_in_squashfs "${pkg}"; then
            pass "squashfs has ${pkg} (purge target Wave B1)"
        else
            warn "squashfs missing ${pkg}"
        fi
    done
else
    warn "squashfs missing — skip telemetry package scan"
fi

if grep -q '預設不上傳' "${PLANS_DIR}/strawwu-security-trust-model.md" || grep -qi 'consent' "${PLANS_DIR}/strawwu-security-trust-model.md"; then
    pass "security plan mentions consent / no auto-upload"
else
    warn "security plan should document bug-report consent"
fi

if [[ -f "${REPO_ROOT}/kernel/config/strawwu.config" ]] || [[ -d "${REPO_ROOT}/kernel" ]]; then
    pass "custom kernel tree present"
else
    warn "kernel tree not found"
fi

preflight_exit "SEC0 security-baseline"

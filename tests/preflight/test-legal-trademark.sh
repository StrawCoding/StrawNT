#!/usr/bin/env bash
# LEG0: Legal / trademark scan on branding overlay.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== LEG0 legal-trademark preflight ==="

require_plan "strawwu-legal-compliance-plan.md"

BRANDING="${REPO_ROOT}/os-image/config/branding"
SCAN_DIRS=(
    "${BRANDING}/etc"
    "${BRANDING}/usr/share/calamares"
    "${BRANDING}/usr/share/plymouth"
    "${BRANDING}/usr/share/themes"
)

forbidden_patterns=(
    'NAME="Ubuntu"'
    'PRETTY_NAME="Ubuntu'
    'Welcome to Ubuntu'
    'ubuntu.com'
)

for pattern in "${forbidden_patterns[@]}"; do
    if grep -Rqi --exclude='os-release' --exclude='casper.conf' -e "${pattern}" "${BRANDING}" 2>/dev/null; then
        fail "forbidden trademark pattern in branding: ${pattern}"
    else
        pass "no branding match for ${pattern}"
    fi
done

if grep -q '^ID=ubuntu$' "${BRANDING}/etc/os-release" 2>/dev/null; then
    pass "os-release keeps ID=ubuntu (casper compat)"
else
    warn "os-release missing ID=ubuntu"
fi

if grep -q 'NAME="StrawWU"' "${BRANDING}/etc/os-release" 2>/dev/null; then
    pass "os-release NAME=StrawWU"
else
    fail "os-release missing NAME=StrawWU"
fi

preflight_exit "LEG0 legal-trademark"

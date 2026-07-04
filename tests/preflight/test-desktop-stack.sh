#!/usr/bin/env bash
# D0: desktop stack baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== D0 desktop-stack preflight ==="

require_plan "strawwu-desktop-plan.md"
require_plan "strawwu-greeter-session-plan.md"
require_file "${REPO_ROOT}/os-image/config/branding/usr/share/themes/StrawWU-Dark/index.theme" "StrawWU-Dark theme"

if has_squashfs; then
    if package_installed_in_squashfs "ubuntu-session"; then
        pass "squashfs still uses ubuntu-session (expected W0)"
    else
        warn "ubuntu-session not in squashfs"
    fi
    if package_installed_in_squashfs "ubuntu-desktop"; then
        pass "squashfs meta ubuntu-desktop present"
    fi
    strawwu_deb_count="$(count_squashfs_packages '^strawwu-')"
    if [[ "${strawwu_deb_count}" -eq 0 ]]; then
        pass "no strawwu-* debs in squashfs yet (W0 baseline)"
    else
        pass "strawwu-* debs in squashfs count=${strawwu_deb_count}"
    fi
else
    warn "squashfs missing — skip desktop package scan"
fi

if [[ -d "${REPO_ROOT}/hub" ]]; then
    pass "strawwu-hub source tree"
else
    fail "missing hub/ directory"
fi

preflight_exit "D0 desktop-stack"

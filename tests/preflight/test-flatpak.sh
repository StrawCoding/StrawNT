#!/usr/bin/env bash
# F0: Flatpak / Flathub baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== F0 flatpak preflight ==="

require_plan "strawwu-flathub-plan.md"

if has_squashfs; then
    flatpak_count="$(count_squashfs_packages '^flatpak$')"
    snapd_count="$(count_squashfs_packages '^snapd$')"
    if [[ "${flatpak_count}" -eq 0 ]]; then
        pass "squashfs has no flatpak yet (W0 baseline)"
    else
        pass "squashfs flatpak installed count=${flatpak_count}"
    fi
    if [[ "${snapd_count}" -gt 0 ]]; then
        pass "squashfs snapd present (to remove in F2)"
    else
        pass "squashfs snapd absent"
    fi
else
    warn "squashfs missing — skip package scan"
fi

if [[ -d "${REPO_ROOT}/packaging/debs/strawwu-flatpak-setup" ]] || [[ -d "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup" ]]; then
    pass "strawwu-flatpak-setup deb scaffold"
else
    warn "strawwu-flatpak-setup deb not yet created (Wave F1)"
fi

preflight_exit "F0 flatpak"

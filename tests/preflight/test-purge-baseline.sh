#!/usr/bin/env bash
# W1-B1: Verify Ubuntu telemetry / Pro / Snap packages purged from rootfs/squashfs.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== W1-B1 purge-baseline preflight ==="

require_plan "strawwu-ubuntu-components-plan.md"
require_file "${REPO_ROOT}/os-image/scripts/chroot-purge-ubuntu-telemetry.sh" "chroot-purge-ubuntu-telemetry.sh"
require_file "${REPO_ROOT}/docs/plans/kickoff/W1-B1-purge.md" "W1-B1 kickoff"

if [[ ! -x "${REPO_ROOT}/os-image/scripts/chroot-purge-ubuntu-telemetry.sh" ]]; then
    chmod +x "${REPO_ROOT}/os-image/scripts/chroot-purge-ubuntu-telemetry.sh"
    pass "chmod +x chroot-purge-ubuntu-telemetry.sh"
fi

marker="${REPO_ROOT}/os-image/work/.purge-ubuntu-telemetry-ok"
if [[ -f "${marker}" ]]; then
    pass "purge marker present (${marker})"
else
    warn "purge marker missing — run: sudo bash os-image/scripts/chroot-purge-ubuntu-telemetry.sh"
fi

if ! has_rootfs && ! has_squashfs; then
    fail "neither rootfs nor squashfs present — run make clone-ubuntu-base first"
fi

for pkg in "${PURGE_TARGET_PACKAGES[@]}"; do
    if has_rootfs && package_installed_in_rootfs "${pkg}"; then
        fail "rootfs still has purge target: ${pkg}"
    elif has_rootfs; then
        pass "rootfs absent ${pkg}"
    fi

    if has_squashfs && package_installed_in_squashfs "${pkg}"; then
        fail "squashfs still has purge target: ${pkg}"
    elif has_squashfs; then
        pass "squashfs absent ${pkg}"
    fi
done

# Must NOT purge casper / keyring / desktop installer stack
if [[ -f "${ROOTFS}/usr/share/keyrings/ubuntu-archive-keyring.gpg" ]] \
    || { has_rootfs && package_installed_in_rootfs ubuntu-keyring; }; then
    pass "retained ubuntu-keyring"
else
    fail "missing required ubuntu-keyring"
fi

if [[ -f "${ROOTFS}/usr/bin/calamares" ]]; then
    pass "retained calamares"
else
    fail "missing required calamares"
fi

for pkg in ubuntu-minimal ubuntu-desktop; do
    if has_rootfs && package_installed_in_rootfs "${pkg}"; then
        pass "retained ${pkg}"
    elif has_rootfs; then
        fail "missing required ${pkg} in rootfs"
    fi
done

if has_rootfs; then
    if [[ -d "${ROOTFS}/snap" ]]; then
        snap_count="$(find "${ROOTFS}/snap" -mindepth 1 -maxdepth 1 ! -name README 2>/dev/null | wc -l || echo 0)"
        if [[ "${snap_count}" -gt 0 ]]; then
            fail "rootfs /snap still has ${snap_count} snap content dirs"
        else
            pass "rootfs /snap empty or stub only"
        fi
    else
        pass "rootfs /snap absent (acceptable pre-F2 or post-purge)"
    fi
fi

if has_squashfs; then
    ubuntu_count="$(list_squashfs_packages | grep -cE '^ubuntu-' || true)"
    pass "squashfs ubuntu-* package count=${ubuntu_count}"
fi

preflight_exit "W1-B1 purge-baseline"

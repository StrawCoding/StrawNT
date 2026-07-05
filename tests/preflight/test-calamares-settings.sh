#!/usr/bin/env bash
# W2-I1: strawwu-calamares-settings — deb replaces ubuntu-common, nosnap, partition gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
BUILD="${DEB_DIR}/build-deb.sh"
CHROOT="${REPO_ROOT}/os-image/scripts/chroot-install-calamares-settings.sh"
OUTPUT_DIR="${DEB_DIR}/output"
INSTALLER="${REPO_ROOT}/os-image/config/calamares-installer"

echo "=== W2-I1 calamares-settings preflight ==="

require_plan "strawwu-installer-plan.md"
require_file "${DEB_DIR}/debian/control" "debian/control"
require_file "${BUILD}" "build-deb.sh"
require_file "${CHROOT}" "chroot-install-calamares-settings.sh"
require_file "${DEB_DIR}/etc/calamares/settings.conf" "settings.conf"
require_file "${DEB_DIR}/etc/calamares/modules/partition.conf" "partition.conf"
require_file "${DEB_DIR}/etc/calamares/modules/packages.conf" "packages.conf"
require_file "${DEB_DIR}/etc/calamares/modules/mount.conf" "mount.conf (upstream exec)"
require_file "${DEB_DIR}/usr/local/lib/calamares/strawwu-post-install-marker.sh" "post-install marker"

for script in "${BUILD}" "${CHROOT}" "${DEB_DIR}/usr/local/lib/calamares/strawwu-post-install-marker.sh"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'strawwu-calamares-settings' "${DEB_DIR}/etc/calamares/modules/packages.conf"; then
    pass "packages.conf removes strawwu-calamares-settings on target install"
else
    fail "packages.conf must remove strawwu-calamares-settings"
fi

if grep -q 'calamares-settings-ubuntu-common' "${DEB_DIR}/etc/calamares/modules/packages.conf"; then
    fail "packages.conf still references calamares-settings-ubuntu-common"
else
    pass "packages.conf no longer references ubuntu-common"
fi

if grep -qE 'type:[[:space:]]*any' "${DEB_DIR}/etc/calamares/modules/partition.conf"; then
    pass "partition.conf devices.type=any"
else
    fail "partition.conf missing devices.type=any"
fi

if grep -qE '^- exec:' "${DEB_DIR}/etc/calamares/settings.conf"; then
    pass "settings.conf has exec phase"
else
    fail "settings.conf missing exec phase"
fi

if grep -q 'branding: strawwu' "${DEB_DIR}/etc/calamares/settings.conf"; then
    pass "settings.conf branding=strawwu"
else
    fail "settings.conf missing branding: strawwu"
fi

if [[ -f "${DEB_DIR}/usr/bin/snap-seed-glue" ]]; then
    fail "deb must not ship snap-seed-glue (W1-F2 nosnap)"
else
    pass "no snap-seed-glue in deb tree"
fi

if grep -q 'Conflicts: calamares-settings-ubuntu-common' "${DEB_DIR}/debian/control"; then
    pass "debian/control Conflicts ubuntu-common"
else
    fail "debian/control missing Conflicts ubuntu-common"
fi

# Build deb on host
rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-calamares-settings_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

# Verify deb contents (no snap, key configs present)
listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./etc/calamares/settings.conf \
    ./etc/calamares/modules/partition.conf \
    ./etc/calamares/modules/mount.conf \
    ./etc/calamares/modules/packages.conf; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

if grep -qF 'snap-seed-glue' <<< "${listing}"; then
    fail "deb packages snap-seed-glue"
else
    pass "deb listing has no snap-seed-glue"
fi

# packages.conf in calamares-installer overlay kept in sync (E2E reference)
if grep -q 'strawwu-calamares-settings' "${INSTALLER}/etc/calamares/modules/packages.conf"; then
    pass "calamares-installer packages.conf synced"
else
    fail "calamares-installer packages.conf out of sync"
fi

MARKER="${REPO_ROOT}/os-image/work/.calamares-settings-ok"
if [[ -f "${MARKER}" ]]; then
    pass "calamares-settings chroot marker present"
else
    warn "calamares-settings marker missing — run: sudo bash os-image/scripts/chroot-install-calamares-settings.sh"
fi

check_ubuntu_common_absent() {
    local label="$1"
    if package_installed_in_filesystem calamares-settings-ubuntu-common; then
        fail "${label} calamares-settings-ubuntu-common still installed"
    else
        pass "${label} ubuntu-common absent"
    fi
}

check_strawwu_installed() {
    local label="$1"
    if package_installed_in_filesystem strawwu-calamares-settings; then
        pass "${label} strawwu-calamares-settings installed"
    else
        fail "${label} strawwu-calamares-settings missing"
    fi
}

check_rootfs_calamares() {
    local root="$1"
    local label="$2"
    if [[ -f "${root}/etc/calamares/settings.conf" ]] \
        && grep -q 'branding: strawwu' "${root}/etc/calamares/settings.conf"; then
        pass "${label} settings.conf branding=strawwu"
    else
        fail "${label} settings.conf missing or wrong branding"
    fi
    if grep -qE 'type:[[:space:]]*any' "${root}/etc/calamares/modules/partition.conf" 2>/dev/null; then
        pass "${label} partition.conf devices.type=any"
    else
        fail "${label} partition.conf invalid"
    fi
    if [[ -f "${root}/usr/bin/snap-seed-glue" ]]; then
        fail "${label} snap-seed-glue still present"
    else
        pass "${label} no snap-seed-glue"
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_rootfs_calamares "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            check_strawwu_installed "rootfs"
            check_ubuntu_common_absent "rootfs"
        fi
    fi
    if has_squashfs; then
        check_rootfs_calamares "${SQUASHFS_ROOT}" "squashfs"
        if [[ -f "${MARKER}" ]]; then
            check_strawwu_installed "squashfs"
            check_ubuntu_common_absent "squashfs"
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W2-I1 calamares-settings"

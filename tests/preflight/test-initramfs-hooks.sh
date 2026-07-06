#!/usr/bin/env bash
# W8-S4: strawwu-initramfs-hooks — installed-target disk boot initramfs hooks.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-initramfs-hooks"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
TARGET_IDENTITY="${REPO_ROOT}/os-image/debs/strawwu-target-identity"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-initramfs-hooks.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/initramfs-hooks-baseline.json"
MANIFEST="${DEB_DIR}/usr/share/strawwu/initramfs-hooks/initramfs-hooks-manifest.yaml"
DISK_BOOT="${DEB_DIR}/etc/initramfs-tools/conf.d/strawwu-disk-boot"
CLI="${DEB_DIR}/usr/bin/strawwu-initramfs-hooks"
CORE="${DEB_DIR}/usr/lib/strawwu-initramfs-hooks/core.py"
TARGET_MANIFEST="${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"
CHROOT_INSTALL="${REPO_ROOT}/os-image/scripts/chroot-install-target-setup.sh"
SPLICE="${REPO_ROOT}/os-image/scripts/initrd-splice.py"

echo "=== W8-S4 initramfs-hooks preflight ==="

require_plan "strawwu-initrd-plan.md"
require_file "${REPO_ROOT}/docs/plans/kickoff/W8-S4-initramfs-hooks.md" "W8-S4 kickoff"
require_file "${DEB_DIR}/debian/control" "strawwu-initramfs-hooks debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-initramfs-hooks debian/postinst"
require_file "${BUILD}" "strawwu-initramfs-hooks build-deb.sh"
require_file "${MANIFEST}" "initramfs-hooks-manifest.yaml"
require_file "${DISK_BOOT}" "strawwu-disk-boot conf.d"
require_file "${CLI}" "strawwu-initramfs-hooks CLI"
require_file "${CORE}" "core.py"
require_file "${UNIT_TEST}" "initramfs-hooks unit test"
require_file "${BASELINE}" "initramfs-hooks-baseline.json"
require_file "${SPLICE}" "initrd-splice.py"

for script in "${BUILD}" "${CLI}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Package: strawwu-initramfs-hooks' "${DEB_DIR}/debian/control"; then
    pass "initramfs-hooks package name"
else
    fail "initramfs-hooks control missing package name"
fi

if grep -q 'Depends: strawwu-initd' "${DEB_DIR}/debian/control"; then
    pass "Depends strawwu-initd"
else
    fail "missing Depends: strawwu-initd"
fi

if grep -q 'schema: strawwu-initramfs-hooks-manifest/v1' "${MANIFEST}"; then
    pass "initramfs-hooks-manifest schema v1"
else
    fail "initramfs-hooks-manifest missing schema"
fi

if grep -q '/usr/share/initramfs-tools/hooks/casper' "${MANIFEST}" \
    && grep -q '/usr/share/initramfs-tools/hooks/live-boot' "${MANIFEST}"; then
    pass "manifest lists casper + live-boot hooks to strip"
else
    fail "manifest missing strip hook paths"
fi

if grep -q 'BOOT=local' "${DISK_BOOT}"; then
    pass "disk-boot conf.d sets BOOT=local"
else
    fail "strawwu-disk-boot missing BOOT=local"
fi

if grep -q 'strip_live_initramfs_hooks' "${CORE}" \
    && grep -q 'install_disk_boot_conf' "${CORE}"; then
    pass "core implements strip + disk-boot"
else
    fail "core missing strip/disk-boot functions"
fi

if grep -q 'inject_strawwu_live_init' "${SPLICE}" \
    && grep -q 'inject_strawwu_live_bottom' "${SPLICE}"; then
    pass "initrd-splice retains ISO live-init/bottom (complement)"
else
    fail "initrd-splice missing live-init/bottom inject"
fi

if grep -q 'strawwu-initramfs-hooks' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-initramfs-hooks"
else
    fail "target-manifest missing strawwu-initramfs-hooks"
fi

hooks_line=$(grep -n 'strawwu-initramfs-hooks' "${TARGET_MANIFEST}" | head -1 | cut -d: -f1)
identity_line=$(grep -n 'strawwu-target-identity' "${TARGET_MANIFEST}" | head -1 | cut -d: -f1)
if [[ -n "${hooks_line}" && -n "${identity_line}" && "${hooks_line}" -lt "${identity_line}" ]]; then
    pass "initramfs-hooks staged before target-identity"
else
    fail "initramfs-hooks must install before target-identity in manifest"
fi

if grep -q 'strawwu-initramfs-hooks' "${CHROOT_INSTALL}" \
    && grep -A2 'strawwu-registry-hooks' "${CHROOT_INSTALL}" | grep -q 'strawwu-initramfs-hooks'; then
    pass "chroot-install stages strawwu-initramfs-hooks deb"
else
    fail "chroot-install-target-setup.sh must stage strawwu-initramfs-hooks"
fi

if python3 "${UNIT_TEST}"; then
    pass "initramfs-hooks unit tests"
else
    fail "initramfs-hooks unit tests"
fi

if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "strawwu-initramfs-hooks build-deb.sh succeeded"
else
    fail "strawwu-initramfs-hooks build-deb.sh failed"
fi

deb="$(ls -1 "${OUTPUT_DIR}"/strawwu-initramfs-hooks_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb}" && -f "${deb}" ]]; then
    pass "initramfs-hooks deb artifact ${deb##*/}"
else
    fail "initramfs-hooks deb artifact missing"
fi

if dpkg-deb -c "${deb}" | grep -q 'etc/initramfs-tools/conf.d/strawwu-disk-boot'; then
    pass "deb contains strawwu-disk-boot conf.d"
else
    fail "deb missing strawwu-disk-boot conf.d"
fi

if dpkg-deb -c "${deb}" | grep -q 'usr/bin/strawwu-initramfs-hooks'; then
    pass "deb contains strawwu-initramfs-hooks CLI"
else
    fail "deb missing CLI"
fi

if dpkg-deb -c "${deb}" | grep -q 'usr/share/strawwu/initramfs-hooks/initramfs-hooks-manifest.yaml'; then
    pass "deb contains initramfs-hooks manifest"
else
    fail "deb missing manifest"
fi

if ! dpkg-deb -c "${deb}" | grep -q 'hooks/casper'; then
    pass "deb does not ship casper hook (strip-only)"
else
    fail "deb must not ship upstream casper hook"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-initramfs-hooks-baseline/v1",
    "wave": "W8-S4",
    "version": version,
    "package": "strawwu-initramfs-hooks",
    "cli": "/usr/bin/strawwu-initramfs-hooks",
    "manifest": "os-image/debs/strawwu-initramfs-hooks/usr/share/strawwu/initramfs-hooks/initramfs-hooks-manifest.yaml",
    "disk_boot_conf": "etc/initramfs-tools/conf.d/strawwu-disk-boot",
    "boot_mode": "local",
    "strip_hooks": [
        "/usr/share/initramfs-tools/hooks/casper",
        "/usr/share/initramfs-tools/hooks/live-boot",
    ],
    "lifecycle_key": "lifecycle.initramfs_hooks",
    "log_path": "/var/log/strawwu/initramfs-hooks.log",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W8-S4 initramfs-hooks"

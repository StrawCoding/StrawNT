#!/usr/bin/env bash
# W3-N2: strawwu-target-setup — Calamares chroot hook + staged target debs.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
CALAMARES_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
INSTALLER="${REPO_ROOT}/os-image/config/calamares-installer"
BUILD="${DEB_DIR}/build-deb.sh"
CHROOT="${REPO_ROOT}/os-image/scripts/chroot-install-target-setup.sh"
UNIT_TEST="${DEB_DIR}/tests/test-target-setup.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/target-setup-baseline.json"
SHELLPROCESS="${CALAMARES_DIR}/etc/calamares/modules/shellprocess_target-setup.conf"
SETTINGS="${CALAMARES_DIR}/etc/calamares/settings.conf"

echo "=== W3-N2 target-setup preflight ==="

require_plan "strawwu-install-init-plan.md"
require_plan "strawwu-observability-debug-plan.md"
require_plan "strawwu-upgrade-recovery-plan.md"

require_file "${DEB_DIR}/debian/control" "strawwu-target-setup debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-target-setup debian/postinst"
require_file "${BUILD}" "strawwu-target-setup build-deb.sh"
require_file "${CHROOT}" "chroot-install-target-setup.sh"
require_file "${DEB_DIR}/usr/bin/strawwu-target-setup" "strawwu-target-setup CLI"
require_file "${DEB_DIR}/usr/lib/strawwu-target-setup/core.py" "core.py"
require_file "${DEB_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml" "target-manifest.yaml"
require_file "${SHELLPROCESS}" "shellprocess_target-setup.conf"
require_file "${UNIT_TEST}" "target-setup unit test"

for script in "${BUILD}" "${CHROOT}" "${DEB_DIR}/usr/bin/strawwu-target-setup" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Depends: strawwu-initd' "${DEB_DIR}/debian/control"; then
    pass "Depends strawwu-initd"
else
    fail "missing Depends: strawwu-initd"
fi

if grep -q 'schema: strawwu-target-manifest/v1' "${DEB_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest schema v1"
else
    fail "target-manifest missing schema"
fi

if grep -q 'strawwu-desktop' "${DEB_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-desktop"
else
    fail "target-manifest missing strawwu-desktop"
fi

if grep -q 'dontChroot: false' "${SHELLPROCESS}"; then
    pass "shellprocess runs in chroot"
else
    fail "shellprocess_target-setup.conf must use dontChroot: false"
fi

if grep -q 'strawwu-target-setup --calamares-chroot' "${SHELLPROCESS}"; then
    pass "shellprocess invokes calamares-chroot"
else
    fail "shellprocess missing calamares-chroot command"
fi

if grep -q 'shellprocess@target_setup' "${SETTINGS}"; then
    pass "settings.conf exec includes target_setup"
else
    fail "settings.conf missing shellprocess@target_setup"
fi

if grep -q 'shellprocess@target_setup' "${INSTALLER}/etc/calamares/settings.conf"; then
    pass "calamares-installer settings synced"
else
    fail "calamares-installer settings out of sync"
fi

if grep -q '/var/log/strawwu/target-setup.log' "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
    pass "observability plan documents target-setup.log"
else
    fail "observability plan missing target-setup.log"
fi

if grep -q 'strawwu-target-setup --repair-only' "${PLANS_DIR}/strawwu-upgrade-recovery-plan.md"; then
    pass "upgrade plan documents repair-only"
else
    fail "upgrade plan missing repair-only"
fi

if grep -q 'strawwu-firstboot' "${DEB_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-firstboot"
else
    fail "target-manifest missing strawwu-firstboot"
fi

if grep -q 'SWU-IN-002' "${DEB_DIR}/usr/lib/strawwu-target-setup/core.py"; then
    pass "core.py references SWU-IN-002"
else
    fail "core.py missing SWU-IN-002"
fi

if python3 "${UNIT_TEST}"; then
    pass "target-setup unit tests"
else
    fail "target-setup unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-target-setup_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/bin/strawwu-target-setup \
    ./usr/lib/strawwu-target-setup/core.py \
    ./usr/share/strawwu/target-setup/target-manifest.yaml; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

if STRAWWU_TARGET_SETUP_DRY_RUN=1 "${DEB_DIR}/usr/bin/strawwu-target-setup" --dry-run; then
    pass "CLI dry-run"
else
    fail "CLI dry-run"
fi

if "${DEB_DIR}/usr/bin/strawwu-target-setup" version | grep -q 'strawwu-target-setup'; then
    pass "CLI version"
else
    fail "CLI version"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-target-setup-baseline/v1",
    "wave": "W3-N2",
    "version": version,
    "package": "strawwu-target-setup",
    "log_path": "/var/log/strawwu/target-setup.log",
    "error_code": "SWU-IN-002",
    "calamares": {
        "shellprocess": "etc/calamares/modules/shellprocess_target-setup.conf",
        "chroot": True,
        "cli_flag": "--calamares-chroot",
    },
    "manifest": "usr/share/strawwu/target-setup/target-manifest.yaml",
    "staged_debs_dir": "usr/share/strawwu/target-setup/staged-debs",
    "repair_flag": "--repair-only",
    "state_cli": "strawwu-initd",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

MARKER="${REPO_ROOT}/os-image/work/.target-setup-ok"
if [[ -f "${MARKER}" ]]; then
    pass "target-setup chroot marker present"
else
    warn "target-setup marker missing — run: sudo bash os-image/scripts/chroot-install-target-setup.sh"
fi

check_installed() {
    local label="$1"
    local pkg="$2"
    if package_installed_in_filesystem "${pkg}"; then
        pass "${label} ${pkg} installed"
    else
        fail "${label} ${pkg} missing"
    fi
}

check_cli() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/strawwu-target-setup" ]]; then
        pass "${label} /usr/bin/strawwu-target-setup present"
    else
        fail "${label} /usr/bin/strawwu-target-setup missing"
    fi
}

check_calamares_hook() {
    local root="$1"
    local label="$2"
    if [[ -f "${root}/etc/calamares/modules/shellprocess_target-setup.conf" ]] \
        && grep -q 'dontChroot: false' "${root}/etc/calamares/modules/shellprocess_target-setup.conf"; then
        pass "${label} calamares target-setup hook"
    else
        fail "${label} calamares target-setup hook missing"
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_cli "${ROOTFS}" "rootfs"
        check_calamares_hook "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "rootfs" strawwu-target-setup
            check_installed "rootfs" strawwu-initd
            check_installed "rootfs" strawwu-session
            check_installed "rootfs" strawwu-desktop
        fi
    fi
    if has_squashfs; then
        check_cli "${SQUASHFS_ROOT}" "squashfs"
        check_calamares_hook "${SQUASHFS_ROOT}" "squashfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "squashfs" strawwu-target-setup
            check_installed "squashfs" strawwu-session
            if [[ -f "${SQUASHFS_ROOT}/usr/share/applications/strawwu-install.desktop" ]]; then
                pass "squashfs strawwu-install.desktop installed"
            else
                warn "squashfs missing strawwu-install.desktop"
            fi
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W3-N2 target-setup"

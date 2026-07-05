#!/usr/bin/env bash
# W5-N3: strawwu-firstboot — GTK4 six-step wizard + initd lifecycle integration.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-firstboot"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
BRANDING="${REPO_ROOT}/os-image/config/branding"
BUILD="${DEB_DIR}/build-deb.sh"
CHROOT="${REPO_ROOT}/os-image/scripts/chroot-install-firstboot.sh"
UNIT_TEST="${DEB_DIR}/tests/test-firstboot.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/firstboot-baseline.json"
MANIFEST="${DEB_DIR}/usr/share/strawwu/firstboot/firstboot-manifest.yaml"
AUTOSTART="${DEB_DIR}/etc/xdg/autostart/strawwu-firstboot.desktop"

echo "=== W5-N3 firstboot preflight ==="

require_plan "strawwu-install-init-plan.md"
require_plan "strawwu-observability-debug-plan.md"
require_plan "strawwu-ux-design-system.md"
require_plan "strawwu-deferred-scope.md"

require_file "${DEB_DIR}/debian/control" "strawwu-firstboot debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-firstboot debian/postinst"
require_file "${BUILD}" "strawwu-firstboot build-deb.sh"
require_file "${CHROOT}" "chroot-install-firstboot.sh"
require_file "${DEB_DIR}/usr/bin/strawwu-firstboot" "strawwu-firstboot CLI"
require_file "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py" "core.py"
require_file "${DEB_DIR}/usr/lib/strawwu-firstboot/wizard_gtk4.py" "wizard_gtk4.py"
require_file "${DEB_DIR}/usr/lib/strawwu-firstboot/i18n.py" "i18n.py"
require_file "${MANIFEST}" "firstboot-manifest.yaml"
require_file "${DEB_DIR}/usr/share/strawwu/locale/firstboot.en.yaml" "firstboot.en.yaml"
require_file "${DEB_DIR}/usr/share/strawwu/locale/firstboot.zh_TW.yaml" "firstboot.zh_TW.yaml"
require_file "${AUTOSTART}" "xdg autostart desktop"
require_file "${DEB_DIR}/usr/share/applications/strawwu-firstboot.desktop" "applications desktop"
require_file "${UNIT_TEST}" "firstboot unit test"
require_file "${BRANDING}/usr/share/strawwu/legal/privacy.html" "branding privacy.html"
require_file "${BRANDING}/usr/share/strawwu/legal/eula.html" "branding eula.html"

for script in "${BUILD}" "${CHROOT}" "${DEB_DIR}/usr/bin/strawwu-firstboot" "${UNIT_TEST}"; do
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

if grep -q 'gir1.2-gtk-4.0' "${DEB_DIR}/debian/control" \
    && grep -q 'gir1.2-adw-1' "${DEB_DIR}/debian/control"; then
    pass "Depends GTK4 + libadwaita"
else
    fail "missing GTK4/libadwaita Depends"
fi

if grep -q 'schema: strawwu-firstboot-manifest/v1' "${MANIFEST}"; then
    pass "firstboot-manifest schema v1"
else
    fail "firstboot-manifest missing schema"
fi

expected_steps="welcome language privacy flathub desktop finish"
for step in ${expected_steps}; do
    if grep -qE "^  - ${step}$" "${MANIFEST}"; then
        pass "manifest step ${step}"
    else
        fail "manifest missing step ${step}"
    fi
done

if grep -q 'strawwu-firstboot' "${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-firstboot"
else
    fail "target-manifest missing strawwu-firstboot"
fi

if grep -q 'bug_upload_opt_in.*False' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py" \
    || grep -q '"bug_upload_opt_in": False' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py"; then
    pass "default bug_upload_opt_in=false"
else
    fail "default bug_upload_opt_in must be false"
fi

if grep -q 'analytics_opt_in.*False' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py" \
    || grep -q '"analytics_opt_in": False' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py"; then
    pass "default analytics_opt_in=false"
else
    fail "default analytics_opt_in must be false"
fi

if grep -q 'SWU-FB-001' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py" \
    && grep -q 'SWU-FB-003' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py"; then
    pass "error codes SWU-FB-001/003"
else
    fail "missing SWU-FB error codes"
fi

if grep -q '/var/log/strawwu/firstboot.log' "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
    pass "observability plan documents firstboot.log"
else
    fail "observability plan missing firstboot.log"
fi

if grep -q 'primary' "${PLANS_DIR}/strawwu-deferred-scope.md" \
    && grep -q 'w5-n3-firstboot' "${PLANS_DIR}/strawwu-deferred-scope.md"; then
    pass "deferred-scope: primary user only"
else
    fail "deferred-scope missing primary-user constraint"
fi

if grep -qi 'ubuntu' "${DEB_DIR}/usr/share/strawwu/locale/firstboot.en.yaml" \
    || grep -qi 'ubuntu' "${DEB_DIR}/usr/share/applications/strawwu-firstboot.desktop"; then
    fail "firstboot assets must not reference Ubuntu trademark"
else
    pass "no Ubuntu trademark in firstboot assets"
fi

if grep -q 'run --autostart' "${AUTOSTART}"; then
    pass "autostart invokes strawwu-firstboot run --autostart"
else
    fail "autostart desktop missing --autostart"
fi

if grep -q 'run_e2e' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py" \
    && grep -q 'FIRSTBOOT_OK' "${DEB_DIR}/usr/lib/strawwu-firstboot/core.py"; then
    pass "core.py E2E marker + run_e2e"
else
    fail "core.py missing E2E marker or run_e2e"
fi

if grep -q '\-\-e2e' "${DEB_DIR}/usr/bin/strawwu-firstboot"; then
    pass "CLI supports --e2e"
else
    fail "CLI missing --e2e flag"
fi

if python3 "${UNIT_TEST}"; then
    pass "firstboot unit tests"
else
    fail "firstboot unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-firstboot_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/bin/strawwu-firstboot \
    ./usr/lib/strawwu-firstboot/core.py \
    ./usr/lib/strawwu-firstboot/wizard_gtk4.py \
    ./usr/share/strawwu/firstboot/firstboot-manifest.yaml \
    ./etc/xdg/autostart/strawwu-firstboot.desktop; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_SETUP_STATE="${tmp_dir}/state.json"
export STRAWWU_INITD_LOG="${tmp_dir}/initd.log"
export STRAWWU_FIRSTBOOT_LOG="${tmp_dir}/firstboot.log"
export STRAWWU_FIRSTBOOT_PREFS="${tmp_dir}/prefs.json"
export STRAWWU_FIRSTBOOT_FORCE=1

INITD_CLI="${REPO_ROOT}/os-image/debs/strawwu-initd/usr/bin/strawwu-initd"
if [[ -x "${INITD_CLI}" ]]; then
    "${INITD_CLI}" init >/dev/null
    if "${DEB_DIR}/usr/bin/strawwu-firstboot" run --dry-run | grep -q 'dry-run'; then
        pass "CLI dry-run"
    else
        fail "CLI dry-run"
    fi
else
    warn "strawwu-initd CLI missing — skipping dry-run integration"
fi

if "${DEB_DIR}/usr/bin/strawwu-firstboot" version | grep -q 'strawwu-firstboot'; then
    pass "CLI version"
else
    fail "CLI version"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-firstboot-baseline/v1",
    "wave": "W5-N3",
    "version": version,
    "package": "strawwu-firstboot",
    "log_path": "/var/log/strawwu/firstboot.log",
    "prefs_path": "/var/lib/strawwu/setup/firstboot-prefs.json",
    "error_codes": {"crash": "SWU-FB-001", "state_mismatch": "SWU-FB-003"},
    "steps": ["welcome", "language", "privacy", "flathub", "desktop", "finish"],
    "manifest": "usr/share/strawwu/firstboot/firstboot-manifest.yaml",
    "autostart": "etc/xdg/autostart/strawwu-firstboot.desktop",
    "state_cli": "strawwu-initd",
    "lifecycle_key": "lifecycle.firstboot",
    "default_opt_in": {"bug_upload": False, "analytics": False},
    "supported_locales": ["zh_TW.UTF-8", "en_US.UTF-8"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

MARKER="${REPO_ROOT}/os-image/work/.firstboot-ok"
if [[ -f "${MARKER}" ]]; then
    pass "firstboot chroot marker present"
else
    warn "firstboot marker missing — run: sudo bash os-image/scripts/chroot-install-firstboot.sh"
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
    if [[ -x "${root}/usr/bin/strawwu-firstboot" ]]; then
        pass "${label} /usr/bin/strawwu-firstboot present"
    else
        fail "${label} /usr/bin/strawwu-firstboot missing"
    fi
}

check_autostart() {
    local root="$1"
    local label="$2"
    if [[ -f "${root}/etc/xdg/autostart/strawwu-firstboot.desktop" ]]; then
        pass "${label} firstboot autostart desktop"
    else
        fail "${label} firstboot autostart desktop missing"
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_cli "${ROOTFS}" "rootfs"
        check_autostart "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "rootfs" strawwu-firstboot
            check_installed "rootfs" strawwu-initd
        elif [[ -f "${REPO_ROOT}/os-image/work/.target-setup-ok" ]]; then
            if package_installed_in_filesystem strawwu-firstboot; then
                pass "rootfs strawwu-firstboot installed"
            else
                warn "rootfs strawwu-firstboot missing — re-run: sudo bash os-image/scripts/chroot-install-target-setup.sh"
            fi
            check_installed "rootfs" strawwu-initd
        fi
    fi
    if has_squashfs; then
        check_cli "${SQUASHFS_ROOT}" "squashfs"
        check_autostart "${SQUASHFS_ROOT}" "squashfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "squashfs" strawwu-firstboot
        elif [[ -f "${REPO_ROOT}/os-image/work/.target-setup-ok" ]]; then
            if package_installed_in_filesystem strawwu-firstboot; then
                pass "squashfs strawwu-firstboot installed"
            else
                warn "squashfs strawwu-firstboot missing — re-run target-setup chroot sync"
            fi
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W5-N3 firstboot"

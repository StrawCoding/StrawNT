#!/usr/bin/env bash
# W5-I3: strawwu-target-identity — GRUB/Plymouth/post-install Calamares chroot hook.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-identity"
CALAMARES_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
INSTALL_INIT="${REPO_ROOT}/os-image/debs/strawwu-install-init"
INSTALLER="${REPO_ROOT}/os-image/config/calamares-installer"
BRANDING="${REPO_ROOT}/os-image/config/branding"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-target-identity.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/target-identity-baseline.json"
MANIFEST="${DEB_DIR}/usr/share/strawwu/target-identity/target-identity-manifest.yaml"
GRUB_DROPIN="${DEB_DIR}/etc/default/grub.d/99-strawwu-identity.cfg"
SHELLPROCESS="${CALAMARES_DIR}/etc/calamares/modules/shellprocess_target-identity.conf"
GRUBCFG="${CALAMARES_DIR}/etc/calamares/modules/grubcfg.conf"
SETTINGS="${CALAMARES_DIR}/etc/calamares/settings.conf"
BOOTLOADER="${CALAMARES_DIR}/etc/calamares/modules/bootloader.conf"

echo "=== W5-I3 target-identity preflight ==="

require_plan "strawwu-installer-plan.md"
require_plan "strawwu-legal-compliance-plan.md"
require_plan "strawwu-observability-debug-plan.md"

require_file "${DEB_DIR}/debian/control" "strawwu-target-identity debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-target-identity debian/postinst"
require_file "${BUILD}" "strawwu-target-identity build-deb.sh"
require_file "${DEB_DIR}/usr/bin/strawwu-target-identity" "strawwu-target-identity CLI"
require_file "${DEB_DIR}/usr/lib/strawwu-target-identity/core.py" "core.py"
require_file "${MANIFEST}" "target-identity-manifest.yaml"
require_file "${GRUB_DROPIN}" "grub drop-in"
require_file "${SHELLPROCESS}" "shellprocess_target-identity.conf"
require_file "${UNIT_TEST}" "target-identity unit test"
require_file "${BRANDING}/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth" "branding plymouth theme"

for script in "${BUILD}" "${DEB_DIR}/usr/bin/strawwu-target-identity" "${UNIT_TEST}"; do
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

if grep -q 'schema: strawwu-target-identity-manifest/v1' "${MANIFEST}"; then
    pass "target-identity-manifest schema v1"
else
    fail "target-identity-manifest missing schema"
fi

if grep -q 'GRUB_DISTRIBUTOR="StrawWU"' "${GRUB_DROPIN}"; then
    pass "grub drop-in GRUB_DISTRIBUTOR=StrawWU"
else
    fail "grub drop-in missing GRUB_DISTRIBUTOR"
fi

if grep -q 'GRUB_DISTRIBUTOR: "StrawWU"' "${GRUBCFG}"; then
    pass "grubcfg.conf defaults GRUB_DISTRIBUTOR"
else
    fail "grubcfg.conf missing GRUB_DISTRIBUTOR default"
fi

if grep -q 'efiBootloaderId: "StrawWU"' "${BOOTLOADER}"; then
    pass "bootloader.conf efiBootloaderId=StrawWU"
else
    fail "bootloader.conf missing efiBootloaderId StrawWU"
fi

if grep -q 'dontChroot: false' "${SHELLPROCESS}"; then
    pass "shellprocess runs in chroot"
else
    fail "shellprocess_target-identity.conf must use dontChroot: false"
fi

if grep -q 'strawwu-target-identity --calamares-chroot' "${SHELLPROCESS}"; then
    pass "shellprocess invokes calamares-chroot"
else
    fail "shellprocess missing calamares-chroot command"
fi

if grep -q 'shellprocess@target_identity' "${SETTINGS}"; then
    pass "settings.conf exec includes target_identity"
else
    fail "settings.conf missing shellprocess@target_identity"
fi

if grep -q 'shellprocess@target_identity' "${INSTALLER}/etc/calamares/settings.conf"; then
    pass "calamares-installer settings synced"
else
    fail "calamares-installer settings out of sync"
fi

if grep -q 'strawwu-target-identity' "${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-target-identity"
else
    fail "target-manifest missing strawwu-target-identity"
fi

if grep -q 'strawwu-target-identity' "${INSTALL_INIT}/usr/share/strawwu/install-init/install-init-manifest.yaml"; then
    pass "install-init-manifest includes strawwu-target-identity"
else
    fail "install-init-manifest missing strawwu-target-identity"
fi

if grep -q 'SWU-IN-003' "${DEB_DIR}/usr/lib/strawwu-target-identity/core.py"; then
    pass "error code SWU-IN-003"
else
    fail "missing SWU-IN-003 error code"
fi

if grep -q '/var/log/strawwu/target-identity.log' "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
    pass "observability plan documents target-identity.log"
else
    fail "observability plan missing target-identity.log"
fi

if grep -qi 'ubuntu' "${GRUB_DROPIN}"; then
    fail "grub drop-in must not reference Ubuntu trademark"
else
    pass "no Ubuntu trademark in grub drop-in"
fi

if python3 "${UNIT_TEST}"; then
    pass "target-identity unit tests"
else
    fail "target-identity unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-target-identity_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/bin/strawwu-target-identity \
    ./usr/lib/strawwu-target-identity/core.py \
    ./etc/default/grub.d/99-strawwu-identity.cfg \
    ./usr/share/strawwu/target-identity/target-identity-manifest.yaml; do
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

INITD_CLI="${REPO_ROOT}/os-image/debs/strawwu-initd/usr/bin/strawwu-initd"
if [[ -x "${INITD_CLI}" ]]; then
    "${INITD_CLI}" init >/dev/null
    if "${DEB_DIR}/usr/bin/strawwu-target-identity" --dry-run apply; then
        pass "CLI apply --dry-run"
    else
        fail "CLI apply --dry-run"
    fi
else
    warn "strawwu-initd CLI missing — skipping dry-run integration"
fi

if "${DEB_DIR}/usr/bin/strawwu-target-identity" version | grep -q 'strawwu-target-identity'; then
    pass "CLI version"
else
    fail "CLI version"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-target-identity-baseline/v1",
    "wave": "W5-I3",
    "version": version,
    "package": "strawwu-target-identity",
    "log_path": "/var/log/strawwu/target-identity.log",
    "marker_path": "/var/lib/strawwu/setup/target-identity.ok",
    "error_code": "SWU-IN-003",
    "grub": {
        "dropin": "/etc/default/grub.d/99-strawwu-identity.cfg",
        "distributor": "StrawWU",
    },
    "plymouth": {"theme": "strawwu-boot"},
    "calamares": {
        "shellprocess": "shellprocess_target-identity.conf",
        "exec_order": "after target_setup, before install_marker",
    },
    "lifecycle_key": "lifecycle.target_identity",
    "manifest": "usr/share/strawwu/target-identity/target-identity-manifest.yaml",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

MARKER="${REPO_ROOT}/os-image/work/.target-setup-ok"
if [[ -f "${MARKER}" ]]; then
    pass "target-setup chroot marker present (identity staged with target stack)"
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

check_grub_dropin() {
    local root="$1"
    local label="$2"
    if [[ -f "${root}/etc/default/grub.d/99-strawwu-identity.cfg" ]] \
        && grep -q 'GRUB_DISTRIBUTOR="StrawWU"' "${root}/etc/default/grub.d/99-strawwu-identity.cfg"; then
        pass "${label} grub drop-in StrawWU"
    elif [[ -f "${MARKER}" ]]; then
        warn "${label} grub drop-in missing — re-run: sudo bash os-image/scripts/chroot-install-target-setup.sh"
    else
        warn "${label} grub drop-in not verified — run chroot-install-target-setup"
    fi
}

check_cli() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/strawwu-target-identity" ]]; then
        pass "${label} /usr/bin/strawwu-target-identity present"
    elif [[ -f "${MARKER}" ]]; then
        warn "${label} strawwu-target-identity missing — re-run chroot-install-target-setup"
    else
        warn "${label} strawwu-target-identity not verified"
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_cli "${ROOTFS}" "rootfs"
        check_grub_dropin "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            if package_installed_in_filesystem strawwu-target-identity; then
                pass "rootfs strawwu-target-identity installed"
            else
                warn "rootfs strawwu-target-identity missing — re-run chroot-install-target-setup"
            fi
        fi
        if [[ -f "${ROOTFS}/etc/calamares/modules/shellprocess_target-identity.conf" ]]; then
            pass "rootfs calamares shellprocess_target-identity.conf"
        elif [[ -f "${MARKER}" ]]; then
            warn "rootfs shellprocess_target-identity.conf missing — re-run chroot-install-target-setup"
        fi
    fi
    if has_squashfs; then
        check_cli "${SQUASHFS_ROOT}" "squashfs"
        check_grub_dropin "${SQUASHFS_ROOT}" "squashfs"
        if [[ -f "${MARKER}" ]]; then
            if package_installed_in_filesystem strawwu-target-identity; then
                pass "squashfs strawwu-target-identity installed"
            else
                warn "squashfs strawwu-target-identity missing — re-run chroot-install-target-setup"
            fi
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W5-I3 target-identity"

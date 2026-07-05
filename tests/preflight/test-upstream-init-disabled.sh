#!/usr/bin/env bash
# W5-B4: strawwu-disable-upstream-init — cloud-init/gnome-initial-setup off + meta purge.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-disable-upstream-init"
CALAMARES_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
INSTALL_INIT="${REPO_ROOT}/os-image/debs/strawwu-install-init"
INSTALLER="${REPO_ROOT}/os-image/config/calamares-installer"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-disable-upstream-init.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/upstream-init-disabled-baseline.json"
MANIFEST="${DEB_DIR}/usr/share/strawwu/disable-upstream-init/disable-upstream-init-manifest.yaml"
CLOUD_DISABLED="${DEB_DIR}/etc/cloud/cloud-init.disabled"
DCONF="${DEB_DIR}/etc/dconf/db/local.d/01-strawwu-no-gnome-initial-setup"
SHELLPROCESS="${CALAMARES_DIR}/etc/calamares/modules/shellprocess_disable-upstream-init.conf"
SETTINGS="${CALAMARES_DIR}/etc/calamares/settings.conf"
TARGET_MANIFEST="${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"

echo "=== W5-B4 disable-upstream-init preflight ==="

require_plan "strawwu-install-init-plan.md"
require_plan "strawwu-observability-debug-plan.md"
require_plan "strawwu-desktop-plan.md"

require_file "${DEB_DIR}/debian/control" "strawwu-disable-upstream-init debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-disable-upstream-init debian/postinst"
require_file "${BUILD}" "strawwu-disable-upstream-init build-deb.sh"
require_file "${DEB_DIR}/usr/bin/strawwu-disable-upstream-init" "strawwu-disable-upstream-init CLI"
require_file "${DEB_DIR}/usr/lib/strawwu-disable-upstream-init/core.py" "core.py"
require_file "${MANIFEST}" "disable-upstream-init-manifest.yaml"
require_file "${CLOUD_DISABLED}" "cloud-init.disabled marker"
require_file "${DCONF}" "dconf keyfile"
require_file "${SHELLPROCESS}" "shellprocess_disable-upstream-init.conf"
require_file "${UNIT_TEST}" "disable-upstream-init unit test"

for script in "${BUILD}" "${DEB_DIR}/usr/bin/strawwu-disable-upstream-init" "${UNIT_TEST}"; do
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

if grep -q 'schema: strawwu-disable-upstream-init-manifest/v1' "${MANIFEST}"; then
    pass "disable-upstream-init-manifest schema v1"
else
    fail "disable-upstream-init-manifest missing schema"
fi

if grep -q 'cloud-init.service' "${MANIFEST}" \
    && grep -q 'gnome-initial-setup.service' "${MANIFEST}"; then
    pass "manifest lists cloud-init + gnome-initial-setup units"
else
    fail "manifest missing masked units"
fi

if grep -q 'ubuntu-desktop' "${MANIFEST}" \
    && grep -q 'ubuntu-session' "${MANIFEST}"; then
    pass "manifest lists upstream metas to purge"
else
    fail "manifest missing upstream meta purge list"
fi

if grep -q 'dontChroot: false' "${SHELLPROCESS}"; then
    pass "shellprocess runs in chroot"
else
    fail "shellprocess_disable-upstream-init.conf must use dontChroot: false"
fi

if grep -q 'strawwu-disable-upstream-init --calamares-chroot' "${SHELLPROCESS}"; then
    pass "shellprocess invokes calamares-chroot"
else
    fail "shellprocess missing calamares-chroot command"
fi

if grep -q 'shellprocess@disable_upstream_init' "${SETTINGS}"; then
    pass "settings.conf exec includes disable_upstream_init"
else
    fail "settings.conf missing shellprocess@disable_upstream_init"
fi

if grep -q 'shellprocess@disable_upstream_init' "${INSTALLER}/etc/calamares/settings.conf"; then
    pass "calamares-installer settings synced"
else
    fail "calamares-installer settings out of sync"
fi

if grep -q 'shellprocess@target_identity' "${SETTINGS}" \
    && grep -q 'shellprocess@disable_upstream_init' "${SETTINGS}" \
    && grep -q 'shellprocess@install_marker' "${SETTINGS}"; then
    identity_line="$(grep -n 'shellprocess@target_identity' "${SETTINGS}" | head -1 | cut -d: -f1)"
    disable_line="$(grep -n 'shellprocess@disable_upstream_init' "${SETTINGS}" | head -1 | cut -d: -f1)"
    marker_line="$(grep -n 'shellprocess@install_marker' "${SETTINGS}" | head -1 | cut -d: -f1)"
    if [[ "${identity_line}" -lt "${disable_line}" && "${disable_line}" -lt "${marker_line}" ]]; then
        pass "exec order target_identity → disable_upstream_init → install_marker"
    else
        fail "exec order wrong for disable_upstream_init"
    fi
else
    fail "settings.conf missing exec chain modules"
fi

if grep -q 'strawwu-disable-upstream-init' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-disable-upstream-init"
else
    fail "target-manifest missing strawwu-disable-upstream-init"
fi

if grep -q 'strawwu-disable-upstream-init' "${INSTALL_INIT}/usr/share/strawwu/install-init/install-init-manifest.yaml"; then
    pass "install-init-manifest includes strawwu-disable-upstream-init"
else
    fail "install-init-manifest missing strawwu-disable-upstream-init"
fi

if grep -q 'SWU-IN-004' "${DEB_DIR}/usr/lib/strawwu-disable-upstream-init/core.py"; then
    pass "error code SWU-IN-004"
else
    fail "missing SWU-IN-004 error code"
fi

if grep -q '/var/log/strawwu/disable-upstream-init.log' "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
    pass "observability plan documents disable-upstream-init.log"
else
    fail "observability plan missing disable-upstream-init.log"
fi

if python3 "${UNIT_TEST}"; then
    pass "disable-upstream-init unit tests"
else
    fail "disable-upstream-init unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-disable-upstream-init_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/bin/strawwu-disable-upstream-init \
    ./usr/lib/strawwu-disable-upstream-init/core.py \
    ./etc/cloud/cloud-init.disabled \
    ./etc/dconf/db/local.d/01-strawwu-no-gnome-initial-setup \
    ./usr/share/strawwu/disable-upstream-init/disable-upstream-init-manifest.yaml; do
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
    if "${DEB_DIR}/usr/bin/strawwu-disable-upstream-init" --dry-run --skip-meta-purge; then
        pass "CLI apply --dry-run"
    else
        fail "CLI apply --dry-run"
    fi
else
    warn "strawwu-initd CLI missing — skipping dry-run integration"
fi

if "${DEB_DIR}/usr/bin/strawwu-disable-upstream-init" version | grep -q 'strawwu-disable-upstream-init'; then
    pass "CLI version"
else
    fail "CLI version"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-upstream-init-disabled-baseline/v1",
    "wave": "W5-B4",
    "version": version,
    "package": "strawwu-disable-upstream-init",
    "log_path": "/var/log/strawwu/disable-upstream-init.log",
    "marker_path": "/var/lib/strawwu/setup/upstream-init-disabled.ok",
    "error_code": "SWU-IN-004",
    "cloud_init": {
        "disabled_marker": "/etc/cloud/cloud-init.disabled",
        "masked_units": [
            "cloud-init.service",
            "cloud-init-local.service",
            "cloud-init.target",
        ],
    },
    "gnome_initial_setup": {
        "dconf_key": "org/gnome/InitialSetup has-completed-setup",
        "masked_units": [
            "gnome-initial-setup.service",
            "gnome-initial-setup-first-login.service",
        ],
    },
    "upstream_metas_purge": [
        "ubuntu-desktop",
        "ubuntu-desktop-minimal",
        "ubuntu-session",
    ],
    "calamares": {
        "shellprocess": "shellprocess_disable-upstream-init.conf",
        "exec_order": "after target_identity, before install_marker",
    },
    "lifecycle_key": "lifecycle.upstream_init_disabled",
    "manifest": "usr/share/strawwu/disable-upstream-init/disable-upstream-init-manifest.yaml",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

MARKER="${REPO_ROOT}/os-image/work/.target-setup-ok"

check_cloud_disabled() {
    local root="$1"
    local label="$2"
    if [[ -f "${root}/etc/cloud/cloud-init.disabled" ]]; then
        pass "${label} cloud-init.disabled present"
    elif [[ -f "${MARKER}" ]]; then
        warn "${label} cloud-init.disabled missing — re-run chroot-install-target-setup"
    else
        warn "${label} cloud-init.disabled not verified"
    fi
}

check_cli() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/strawwu-disable-upstream-init" ]]; then
        pass "${label} /usr/bin/strawwu-disable-upstream-init present"
    elif [[ -f "${MARKER}" ]]; then
        warn "${label} strawwu-disable-upstream-init missing — re-run chroot-install-target-setup"
    else
        warn "${label} strawwu-disable-upstream-init not verified"
    fi
}

check_no_upstream_desktop() {
    local label="$1"
    if package_installed_in_filesystem "ubuntu-desktop"; then
        if [[ -f "${MARKER}" ]]; then
            warn "${label} still has ubuntu-desktop — re-run chroot-install-target-setup"
        else
            pass "${label} ubuntu-desktop present (pre-W5-B4 transition)"
        fi
    else
        pass "${label} absent ubuntu-desktop"
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_cli "${ROOTFS}" "rootfs"
        check_cloud_disabled "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            if package_installed_in_filesystem strawwu-disable-upstream-init; then
                pass "rootfs strawwu-disable-upstream-init installed"
            else
                warn "rootfs strawwu-disable-upstream-init missing — re-run chroot-install-target-setup"
            fi
        fi
        check_no_upstream_desktop "rootfs"
    fi
    if has_squashfs; then
        check_cli "${SQUASHFS_ROOT}" "squashfs"
        check_cloud_disabled "${SQUASHFS_ROOT}" "squashfs"
        check_no_upstream_desktop "squashfs"
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W5-B4 disable-upstream-init"

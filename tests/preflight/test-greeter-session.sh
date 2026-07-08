#!/usr/bin/env bash
# W5-GRT: strawwu-greeter — GDM theme + strawwu-session defaults (GRT0–GRT2).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-greeter"
SESSION_DIR="${REPO_ROOT}/os-image/debs/strawwu-session"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
INSTALL_INIT="${REPO_ROOT}/os-image/debs/strawwu-install-init"
BRANDING="${REPO_ROOT}/os-image/config/branding"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-greeter.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/greeter-session-baseline.json"
MANIFEST="${DEB_DIR}/usr/share/strawwu/greeter/greeter-manifest.yaml"
DCONF="${DEB_DIR}/usr/share/strawwu/greeter/greeter.dconf-defaults"
GDM_DCONF="${DEB_DIR}/etc/gdm3/greeter.dconf-defaults"
CSS="${DEB_DIR}/usr/share/gnome-shell/theme/strawwu-greeter.css"
LIVE_EXAMPLE="${DEB_DIR}/usr/share/strawwu/greeter/live-autologin.conf.example"

echo "=== W5-GRT greeter-session preflight ==="

require_plan "strawwu-greeter-session-plan.md"
require_plan "strawwu-observability-debug-plan.md"
require_plan "strawwu-deferred-scope.md"

require_file "${DEB_DIR}/debian/control" "strawwu-greeter debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-greeter debian/postinst"
require_file "${BUILD}" "strawwu-greeter build-deb.sh"
require_file "${DEB_DIR}/usr/bin/strawwu-greeter" "strawwu-greeter CLI"
require_file "${DEB_DIR}/usr/lib/strawwu-greeter/core.py" "core.py"
require_file "${MANIFEST}" "greeter-manifest.yaml"
require_file "${DCONF}" "greeter.dconf-defaults template"
require_file "${GDM_DCONF}" "etc/gdm3/greeter.dconf-defaults"
require_file "${CSS}" "strawwu-greeter.css"
require_file "${LIVE_EXAMPLE}" "live-autologin.conf.example"
require_file "${UNIT_TEST}" "test-greeter.py"
require_file "${SESSION_DIR}/usr/share/xsessions/strawwu-session.desktop" "strawwu-session xsessions"
require_file "${BRANDING}/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg" "distributor logo"

for script in "${BUILD}" "${DEB_DIR}/usr/bin/strawwu-greeter" "${UNIT_TEST}"; do
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

if grep -q 'strawwu-session' "${DEB_DIR}/debian/control"; then
    pass "Depends strawwu-session"
else
    fail "missing Depends: strawwu-session"
fi

if grep -q 'schema: strawwu-greeter-manifest/v1' "${MANIFEST}"; then
    pass "greeter-manifest schema v1"
else
    fail "greeter-manifest missing schema"
fi

if grep -q "default_session: strawwu-session" "${MANIFEST}"; then
    pass "manifest default_session=strawwu-session (GRT1)"
else
    fail "manifest missing default_session"
fi

if grep -q "gtk-theme='StrawWU-Dark'" "${DCONF}" \
    && grep -q "disable-user-list=true" "${DCONF}"; then
    pass "greeter dconf StrawWU-Dark + single-user list off"
else
    fail "greeter dconf missing StrawWU-Dark or disable-user-list"
fi

if grep -q 'build-iso.sh' "${MANIFEST}" \
    && grep -q 'AutomaticLogin=ubuntu' "${LIVE_EXAMPLE}"; then
    pass "GRT2 live autologin documented (build-iso + example)"
else
    fail "GRT2 live autologin reference missing"
fi

if grep -q 'strawwu-greeter' "${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-greeter"
else
    fail "target-manifest missing strawwu-greeter"
fi

if grep -q 'strawwu-greeter' "${INSTALL_INIT}/usr/share/strawwu/install-init/install-init-manifest.yaml"; then
    pass "install-init-manifest includes strawwu-greeter"
else
    fail "install-init-manifest missing strawwu-greeter"
fi

if grep -q 'X-GDM-SessionRegisters=true' "${SESSION_DIR}/usr/share/xsessions/strawwu-session.desktop"; then
    pass "strawwu-session GDM registration (GRT1)"
else
    fail "strawwu-session missing X-GDM-SessionRegisters"
fi

if grep -q 'GNOME_SHELL_SESSION_MODE=strawwu' "${SESSION_DIR}/usr/bin/strawwu-session"; then
    pass "strawwu-session launcher uses strawwu shell mode"
else
    fail "strawwu-session missing strawwu shell mode"
fi

if grep -q 'SWU-GR-001' "${DEB_DIR}/usr/lib/strawwu-greeter/core.py"; then
    pass "error code SWU-GR-001"
else
    fail "missing SWU-GR-001 error code"
fi

if grep -q '/var/log/strawwu/greeter.log' "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
    pass "observability plan documents greeter.log"
else
    fail "observability plan missing greeter.log"
fi

if grep -q 'w5-grt-session' "${PLANS_DIR}/strawwu-deferred-scope.md"; then
    pass "deferred-scope: single-user GDM greeter"
else
    fail "deferred-scope missing w5-grt-session constraint"
fi

for f in "${DCONF}" "${GDM_DCONF}" "${CSS}"; do
    if grep -qi 'ubuntu' "${f}"; then
        fail "Ubuntu trademark in $(basename "${f}")"
    else
        pass "no Ubuntu trademark in $(basename "${f}")"
    fi
done

if grep -qi 'ubuntu' "${MANIFEST}" && ! grep -q 'casper_live_user' "${MANIFEST}"; then
    fail "Ubuntu trademark in greeter-manifest.yaml"
else
    pass "greeter-manifest trademark OK (casper live user reference allowed)"
fi

if python3 "${UNIT_TEST}"; then
    pass "greeter unit tests"
else
    fail "greeter unit tests"
fi

# Avoid rm -rf on output/ — concurrent preflight runs can race on directory removal.
mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR}/strawwu-greeter_"*.deb 2>/dev/null || true
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-greeter_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/bin/strawwu-greeter \
    ./usr/lib/strawwu-greeter/core.py \
    ./etc/gdm3/greeter.dconf-defaults \
    ./usr/share/gnome-shell/theme/strawwu-greeter.css \
    ./usr/share/strawwu/greeter/greeter-manifest.yaml; do
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
    if "${DEB_DIR}/usr/bin/strawwu-greeter" --dry-run apply; then
        pass "CLI apply --dry-run"
    else
        fail "CLI apply --dry-run"
    fi
else
    warn "strawwu-initd CLI missing — skipping dry-run integration"
fi

if "${DEB_DIR}/usr/bin/strawwu-greeter" version | grep -q 'strawwu-greeter'; then
    pass "CLI version"
else
    fail "CLI version"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-greeter-session-baseline/v1",
    "wave": "W5-GRT",
    "version": version,
    "package": "strawwu-greeter",
    "log_path": "/var/log/strawwu/greeter.log",
    "marker_path": "/var/lib/strawwu/setup/greeter.ok",
    "error_code": "SWU-GR-001",
    "grt": {
        "grt0": "GDM theme StrawWU-Dark + distributor logo CSS",
        "grt1": "DefaultSession=strawwu-session",
        "grt2": "live autologin via build-iso.sh (AutomaticLogin=ubuntu)",
    },
    "default_session": "strawwu-session",
    "theme": {
        "gtk": "StrawWU-Dark",
        "css": "/usr/share/gnome-shell/theme/strawwu-greeter.css",
    },
    "single_user": {"disable_user_list": True},
    "lifecycle_key": "lifecycle.greeter",
    "manifest": "usr/share/strawwu/greeter/greeter-manifest.yaml",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

MARKER="${REPO_ROOT}/os-image/work/.target-setup-ok"
check_greeter_files() {
    local root="$1"
    local label="$2"
    if [[ -f "${root}/etc/gdm3/greeter.dconf-defaults" ]] \
        && grep -q "StrawWU-Dark" "${root}/etc/gdm3/greeter.dconf-defaults"; then
        pass "${label} greeter.dconf-defaults StrawWU-Dark"
    elif [[ -f "${MARKER}" ]]; then
        warn "${label} greeter.dconf-defaults missing — re-run chroot-install-target-setup"
    else
        warn "${label} greeter.dconf-defaults not verified — run chroot-install-target-setup"
    fi
    if [[ -x "${root}/usr/bin/strawwu-greeter" ]]; then
        pass "${label} /usr/bin/strawwu-greeter present"
    elif [[ -f "${MARKER}" ]]; then
        warn "${label} strawwu-greeter missing — re-run chroot-install-target-setup"
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_greeter_files "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            if package_installed_in_filesystem strawwu-greeter; then
                pass "rootfs strawwu-greeter installed"
            else
                warn "rootfs strawwu-greeter missing — re-run chroot-install-target-setup"
            fi
        fi
    fi
    if has_squashfs; then
        check_greeter_files "${SQUASHFS_ROOT}" "squashfs"
        if [[ -f "${MARKER}" ]]; then
            if package_installed_in_filesystem strawwu-greeter; then
                pass "squashfs strawwu-greeter installed"
            else
                warn "squashfs strawwu-greeter missing — re-run chroot-install-target-setup"
            fi
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W5-GRT greeter-session"

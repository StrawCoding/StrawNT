#!/usr/bin/env bash
# W3-D1: strawwu-session + strawwu-desktop meta baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

SESSION_DIR="${REPO_ROOT}/os-image/debs/strawwu-session"
DESKTOP_DIR="${REPO_ROOT}/os-image/debs/strawwu-desktop"
SESSION_BUILD="${SESSION_DIR}/build-deb.sh"
DESKTOP_BUILD="${DESKTOP_DIR}/build-deb.sh"
SESSION_TEST="${SESSION_DIR}/tests/test-session.py"
DESKTOP_TEST="${DESKTOP_DIR}/tests/test-meta.py"
BASELINE="${BASELINES_DIR}/desktop-baseline.json"

FORBIDDEN_META=(
    snapd
    snap-confine
    apport
    whoopsie
    ubuntu-report
    ubuntu-pro-client
)

echo "=== W3-D1 desktop-stack preflight ==="

require_plan "strawwu-desktop-plan.md"
require_plan "strawwu-greeter-session-plan.md"
require_file "${REPO_ROOT}/os-image/config/branding/usr/share/themes/StrawWU-Dark/index.theme" "StrawWU-Dark theme"

if [[ -d "${REPO_ROOT}/hub" ]]; then
    pass "strawwu-hub source tree"
else
    fail "missing hub/ directory"
fi

# --- strawwu-session ---
require_file "${SESSION_DIR}/debian/control" "strawwu-session debian/control"
require_file "${SESSION_DIR}/debian/postinst" "strawwu-session debian/postinst"
require_file "${SESSION_BUILD}" "strawwu-session build-deb.sh"
require_file "${SESSION_DIR}/usr/bin/strawwu-session" "strawwu-session launcher"
require_file "${SESSION_DIR}/usr/share/xsessions/strawwu-session.desktop" "xsessions desktop"
require_file "${SESSION_DIR}/usr/share/gnome-session/sessions/strawwu.session" "gnome session"
require_file "${SESSION_DIR}/etc/xdg/autostart/strawwu-hub-autostart.desktop" "hub autostart"
require_file "${SESSION_TEST}" "test-session.py"

for script in "${SESSION_BUILD}" "${SESSION_DIR}/usr/bin/strawwu-session" "${SESSION_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'X-GDM-SessionRegisters=true' "${SESSION_DIR}/usr/share/xsessions/strawwu-session.desktop"; then
    pass "strawwu-session GDM registration"
else
    fail "strawwu-session missing X-GDM-SessionRegisters"
fi

if grep -q 'Name=StrawWU' "${SESSION_DIR}/usr/share/gnome-session/sessions/strawwu.session"; then
    pass "strawwu gnome session Name=StrawWU"
else
    fail "strawwu.session missing Name=StrawWU"
fi

if grep -q 'gnome-session --session=strawwu' "${SESSION_DIR}/usr/bin/strawwu-session"; then
    pass "launcher uses gnome-session --session=strawwu"
else
    fail "launcher missing gnome-session --session=strawwu"
fi

if python3 "${SESSION_TEST}"; then
    pass "strawwu-session unit tests"
else
    fail "strawwu-session unit tests"
fi

rm -rf "${SESSION_DIR}/output"
if STRAWWU_VERSION="${VERSION}" bash "${SESSION_BUILD}"; then
    pass "strawwu-session build-deb.sh succeeded"
else
    fail "strawwu-session build-deb.sh failed"
fi

session_deb="$(ls -1 "${SESSION_DIR}/output"/strawwu-session_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${session_deb}" && -f "${session_deb}" ]]; then
    pass "strawwu-session deb artifact ${session_deb##*/}"
else
    fail "strawwu-session deb artifact missing"
fi

# --- strawwu-desktop meta ---
require_file "${DESKTOP_DIR}/debian/control" "strawwu-desktop debian/control"
require_file "${DESKTOP_DIR}/debian/postinst" "strawwu-desktop debian/postinst"
require_file "${DESKTOP_BUILD}" "strawwu-desktop build-deb.sh"
require_file "${DESKTOP_TEST}" "test-meta.py"
require_file "${DESKTOP_DIR}/usr/share/doc/strawwu-desktop/README" "desktop meta README"

for script in "${DESKTOP_BUILD}" "${DESKTOP_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'strawwu-session' "${DESKTOP_DIR}/debian/control"; then
    pass "strawwu-desktop Depends strawwu-session"
else
    fail "strawwu-desktop missing strawwu-session Depends"
fi

if grep -q 'Section: metapackages' "${DESKTOP_DIR}/debian/control"; then
    pass "strawwu-desktop metapackage section"
else
    fail "strawwu-desktop not a metapackage"
fi

meta_bad=0
for pkg in "${FORBIDDEN_META[@]}"; do
    if grep -qiE "(Depends|Recommends|Pre-Depends):.*\\b${pkg}\\b" "${DESKTOP_DIR}/debian/control"; then
        fail "strawwu-desktop control references forbidden ${pkg}"
        meta_bad=1
    fi
done
if [[ "${meta_bad}" -eq 0 ]]; then
    pass "strawwu-desktop control has no forbidden telemetry/snap deps"
fi

if python3 "${DESKTOP_TEST}"; then
    pass "strawwu-desktop meta unit tests"
else
    fail "strawwu-desktop meta unit tests"
fi

rm -rf "${DESKTOP_DIR}/output"
if STRAWWU_VERSION="${VERSION}" bash "${DESKTOP_BUILD}"; then
    pass "strawwu-desktop build-deb.sh succeeded"
else
    fail "strawwu-desktop build-deb.sh failed"
fi

desktop_deb="$(ls -1 "${DESKTOP_DIR}/output"/strawwu-desktop_"${VERSION}"_amd64.deb 2>/dev/null | head -1)"
if [[ -n "${desktop_deb}" && -f "${desktop_deb}" ]]; then
    pass "strawwu-desktop deb artifact ${desktop_deb##*/}"
else
    fail "strawwu-desktop deb artifact missing"
fi

# --- squashfs context (W0 → W3 transition) ---
if has_squashfs; then
    if package_installed_in_squashfs "ubuntu-session"; then
        pass "squashfs still has ubuntu-session (transition; W5-B4 replaces)"
    else
        warn "ubuntu-session not in squashfs"
    fi
    if package_installed_in_squashfs "ubuntu-desktop"; then
        pass "squashfs still has ubuntu-desktop (transition; W5-B4 replaces)"
    fi
    strawwu_deb_count="$(count_squashfs_packages '^strawwu-')"
    if [[ "${strawwu_deb_count}" -eq 0 ]]; then
        pass "squashfs strawwu-* debs not yet installed (deb scaffolds ready W3-D1)"
    else
        pass "strawwu-* debs in squashfs count=${strawwu_deb_count}"
    fi
else
    warn "squashfs missing — skip installed package scan"
fi

# --- desktop baseline JSON ---
baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
forbidden = [
    "snapd", "snap-confine", "apport", "whoopsie",
    "ubuntu-report", "ubuntu-pro-client",
]
data = {
    "schema": "strawwu-desktop-baseline/v1",
    "wave": "W3-D1",
    "version": version,
    "packages": {
        "strawwu-session": {
            "path": "os-image/debs/strawwu-session",
            "gdm_session": "strawwu-session",
            "interim_compositor": "gnome-shell",
            "shell_target_wave": "W4-D2",
        },
        "strawwu-desktop": {
            "path": "os-image/debs/strawwu-desktop",
            "replaces_ubuntu_desktop_wave": "W5-B4",
            "audit_wave": "W6-B5",
        },
    },
    "forbidden_meta_deps": forbidden,
    "session_registered": True,
    "meta_scaffold_ready": True,
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W3-D1 desktop-stack"

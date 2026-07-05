#!/usr/bin/env bash
# W4-D2: strawwu-shell — GNOME Shell fork profile + built-in dock.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

SHELL_DIR="${REPO_ROOT}/os-image/debs/strawwu-shell"
SESSION_DIR="${REPO_ROOT}/os-image/debs/strawwu-session"
DESKTOP_DIR="${REPO_ROOT}/os-image/debs/strawwu-desktop"
BUILD="${SHELL_DIR}/build-deb.sh"
UNIT_TEST="${SHELL_DIR}/tests/test-shell.py"
BASELINE="${BASELINES_DIR}/shell-baseline.json"

UBUNTU_EXTENSIONS=(
    ubuntu-dock@ubuntu.com
    ubuntu-appindicators@ubuntu.com
    ding@rastersoft.com
)

echo "=== W4-D2 strawwu-shell preflight ==="

require_plan "strawwu-desktop-plan.md"
require_plan "strawwu-deferred-scope.md"
require_file "${REPO_ROOT}/os-image/config/branding/usr/share/themes/StrawWU-Dark/gnome-shell/gnome-shell.css" "StrawWU-Dark gnome-shell theme"

require_file "${SHELL_DIR}/debian/control" "strawwu-shell debian/control"
require_file "${SHELL_DIR}/debian/postinst" "strawwu-shell debian/postinst"
require_file "${BUILD}" "strawwu-shell build-deb.sh"
require_file "${SHELL_DIR}/usr/bin/strawwu-shell" "strawwu-shell launcher"
require_file "${SHELL_DIR}/usr/share/gnome-shell/modes/strawwu.json" "strawwu session mode"
require_file "${SHELL_DIR}/usr/share/gnome-shell/extensions/strawwu-dock@strawwu/extension.js" "built-in dock extension"
require_file "${SHELL_DIR}/usr/share/gnome-shell/extensions/strawwu-dock@strawwu/metadata.json" "dock metadata"
require_file "${SHELL_DIR}/usr/share/strawwu/shell/shell.yaml" "shell profile manifest"
require_file "${SHELL_DIR}/usr/share/strawwu/shell/dock.yaml" "dock config"
require_file "${SHELL_DIR}/usr/share/strawwu/shell/disabled-extensions.json" "disabled extensions manifest"
require_file "${SHELL_DIR}/usr/share/glib-2.0/schemas/10_strawwu-shell.gschema.override" "shell gschema override"
require_file "${UNIT_TEST}" "test-shell.py"

for script in "${BUILD}" "${SHELL_DIR}/usr/bin/strawwu-shell" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -qE 'GNOME_SHELL_SESSION_MODE=(strawwu|"?\$\{GNOME_SHELL_SESSION_MODE:-strawwu\}")' "${SHELL_DIR}/usr/bin/strawwu-shell"; then
    pass "launcher sets strawwu session mode"
else
    fail "launcher missing strawwu session mode default"
fi

if grep -q 'strawwu-dock@strawwu' "${SHELL_DIR}/usr/share/gnome-shell/modes/strawwu.json"; then
    pass "session mode enables built-in dock"
else
    fail "strawwu.json missing strawwu-dock@strawwu"
fi

mode_bad=0
for ext in "${UBUNTU_EXTENSIONS[@]}"; do
    if grep -qF "${ext}" "${SHELL_DIR}/usr/share/gnome-shell/modes/strawwu.json"; then
        fail "strawwu.json must not enable ubuntu extension ${ext}"
        mode_bad=1
    fi
done
if [[ "${mode_bad}" -eq 0 ]]; then
    pass "session mode excludes ubuntu extensions from enabled list"
fi

if grep -q 'strawwu-shell' "${SESSION_DIR}/debian/control"; then
    pass "strawwu-session Depends strawwu-shell"
else
    fail "strawwu-session missing strawwu-shell Depends"
fi

if grep -q 'GNOME_SHELL_SESSION_MODE=strawwu' "${SESSION_DIR}/usr/bin/strawwu-session"; then
    pass "strawwu-session uses strawwu shell mode"
else
    fail "strawwu-session still on interim ubuntu mode"
fi

if grep -q 'strawwu-shell' "${DESKTOP_DIR}/debian/control"; then
    pass "strawwu-desktop Depends strawwu-shell"
else
    fail "strawwu-desktop missing strawwu-shell Depends"
fi

if grep -q 'strawwu-shell' "${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-shell"
else
    fail "target-manifest missing strawwu-shell"
fi

if python3 "${UNIT_TEST}"; then
    pass "strawwu-shell unit tests"
else
    fail "strawwu-shell unit tests"
fi

rm -rf "${SHELL_DIR}/output"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "strawwu-shell build-deb.sh succeeded"
else
    fail "strawwu-shell build-deb.sh failed"
fi

shell_deb="$(ls -1 "${SHELL_DIR}/output"/strawwu-shell_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${shell_deb}" && -f "${shell_deb}" ]]; then
    pass "strawwu-shell deb artifact ${shell_deb##*/}"
else
    fail "strawwu-shell deb artifact missing"
fi

listing="$(dpkg-deb -c "${shell_deb}")"
for rel in \
    ./usr/bin/strawwu-shell \
    ./usr/share/gnome-shell/modes/strawwu.json \
    ./usr/share/gnome-shell/extensions/strawwu-dock@strawwu/extension.js \
    ./usr/share/strawwu/shell/shell.yaml; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
dpkg-deb -x "${shell_deb}" "${tmpdir}"
chmod +x "${tmpdir}/usr/bin/strawwu-shell"

if grep -q 'strawwu' "${tmpdir}/usr/bin/strawwu-shell"; then
    pass "unpacked strawwu-shell launcher valid"
else
    fail "unpacked launcher invalid"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-shell-baseline/v1",
    "wave": "W4-D2",
    "version": version,
    "package": "strawwu-shell",
    "launcher": "/usr/bin/strawwu-shell",
    "session_mode": "strawwu",
    "builtin_dock_extension": "strawwu-dock@strawwu",
    "fork_strategy": "session-mode-overlay",
    "extension_public_api": False,
    "disabled_ubuntu_extensions": [
        "ubuntu-dock@ubuntu.com",
        "ubuntu-appindicators@ubuntu.com",
        "ding@rastersoft.com",
        "desktop-icons@csoriano",
    ],
    "manifests": {
        "shell": "usr/share/strawwu/shell/shell.yaml",
        "dock": "usr/share/strawwu/shell/dock.yaml",
        "disabled": "usr/share/strawwu/shell/disabled-extensions.json",
    },
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W4-D2 strawwu-shell"

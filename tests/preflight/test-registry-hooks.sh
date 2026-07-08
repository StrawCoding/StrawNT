#!/usr/bin/env bash
# W5-R4: install pipeline hooks — Linux/Flatpak scan into app registry.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-registry-hooks"
DESKTOP_DIR="${REPO_ROOT}/os-image/debs/strawwu-desktop"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
COMPONENTS="${REPO_ROOT}/components"
CRATE_DIR="${COMPONENTS}/strawwu-app-registry"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-registry-hooks.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/registry-hooks-baseline.json"
MANIFEST="${DEB_DIR}/usr/share/strawwu/registry-hooks/registry-hooks-manifest.yaml"
APT_HOOK="${DEB_DIR}/usr/lib/strawwu-registry-hooks/apt-post-invoke"
FLATPAK_TRIGGER="${DEB_DIR}/usr/share/flatpak/triggers/strawwu-registry-scan"
SCAN_CLI="${DEB_DIR}/usr/bin/strawwu-registry-scan"
REGISTRY_BIN="${COMPONENTS}/target/debug/strawwu-app-registry"

echo "=== W5-R4 registry-hooks preflight ==="

require_plan "strawwu-app-registry-plan.md"

require_file "${DEB_DIR}/debian/control" "strawwu-registry-hooks debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-registry-hooks debian/postinst"
require_file "${BUILD}" "strawwu-registry-hooks build-deb.sh"
require_file "${MANIFEST}" "registry-hooks-manifest.yaml"
require_file "${SCAN_CLI}" "strawwu-registry-scan CLI"
require_file "${APT_HOOK}" "apt-post-invoke hook"
require_file "${FLATPAK_TRIGGER}" "flatpak trigger"
require_file "${DEB_DIR}/etc/apt/apt.conf.d/99strawwu-registry-hooks" "apt.conf.d hook"
require_file "${UNIT_TEST}" "registry-hooks unit test"

for script in "${BUILD}" "${SCAN_CLI}" "${APT_HOOK}" "${FLATPAK_TRIGGER}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Package: strawwu-registry-hooks' "${DEB_DIR}/debian/control"; then
    pass "registry-hooks package name"
else
    fail "registry-hooks control missing package name"
fi

if grep -q 'strawwu-desktop-actions' "${DEB_DIR}/debian/control"; then
    pass "Depends strawwu-desktop-actions (registry CLI)"
else
    fail "registry-hooks missing Depends: strawwu-desktop-actions"
fi

if grep -q 'schema: strawwu-registry-hooks-manifest/v1' "${MANIFEST}"; then
    pass "registry-hooks-manifest schema v1"
else
    fail "registry-hooks-manifest missing schema"
fi

if grep -q 'DPkg::Post-Invoke' "${DEB_DIR}/etc/apt/apt.conf.d/99strawwu-registry-hooks"; then
    pass "APT post-invoke hook configured"
else
    fail "APT post-invoke hook missing"
fi

if grep -q 'strawwu-registry-scan --linux' "${APT_HOOK}"; then
    pass "APT hook scans Linux desktops"
else
    fail "APT hook missing Linux scan"
fi

if grep -q 'strawwu-registry-scan --flatpak' "${FLATPAK_TRIGGER}"; then
    pass "Flatpak trigger scans Flatpak apps"
else
    fail "Flatpak trigger missing flatpak scan"
fi

if grep -q 'strawwu-registry-hooks' "${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-registry-hooks"
else
    fail "target-manifest missing strawwu-registry-hooks"
fi

if grep -q 'strawwu-registry-hooks' "${DESKTOP_DIR}/debian/control"; then
    pass "strawwu-desktop Recommends registry-hooks"
else
    fail "strawwu-desktop missing registry-hooks dependency"
fi

if grep -q 'scan' "${CRATE_DIR}/src/cli.rs" && grep -q 'upsert_from_scan' "${CRATE_DIR}/src/registry.rs"; then
    pass "app-registry scan API present"
else
    fail "app-registry scan API missing"
fi

if (cd "${COMPONENTS}" && cargo build --package strawwu-app-registry -q); then
    pass "cargo build strawwu-app-registry"
else
    fail "cargo build strawwu-app-registry"
fi

require_file "${REGISTRY_BIN}" "strawwu-app-registry binary"

if (cd "${COMPONENTS}" && cargo test --package strawwu-app-registry -q); then
    pass "cargo test strawwu-app-registry"
else
    fail "cargo test strawwu-app-registry"
fi

if python3 "${UNIT_TEST}"; then
    pass "registry-hooks unit tests"
else
    fail "registry-hooks unit tests"
fi

if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "strawwu-registry-hooks build-deb.sh succeeded"
else
    fail "strawwu-registry-hooks build-deb.sh failed"
fi

deb="$(ls -1 "${OUTPUT_DIR}"/strawwu-registry-hooks_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb}" && -f "${deb}" ]]; then
    pass "registry-hooks deb artifact ${deb##*/}"
else
    fail "registry-hooks deb artifact missing"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"
export STRAWWU_APP_REGISTRY_CLI="${REGISTRY_BIN}"
export STRAWWU_LINUX_DESKTOP_DIRS="${tmp_dir}/applications"
mkdir -p "${STRAWWU_LINUX_DESKTOP_DIRS}"

cat > "${STRAWWU_LINUX_DESKTOP_DIRS}/demo-linux-app.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Demo Linux App
Exec=/usr/bin/demo-linux
EOF

flatpak_fixture="${tmp_dir}/flatpak.list"
printf '%s\n' 'org.gnome.Calculator	Calculator' > "${flatpak_fixture}"
export STRAWWU_FLATPAK_LIST_FILE="${flatpak_fixture}"

# Cache CLI JSON once — pipefail + grep -q early-close trips SIGPIPE in Rust stdout.
linux_scan_json="$("${REGISTRY_BIN}" scan --linux --json 2>/dev/null || true)"
if grep -q 'demo-linux-app' <<<"${linux_scan_json}"; then
    pass "CLI scan --linux discovers desktop app"
else
    fail "CLI scan --linux missing demo-linux-app"
fi

flatpak_scan_json="$("${REGISTRY_BIN}" scan --flatpak --json 2>/dev/null || true)"
if grep -q 'org.gnome.calculator' <<<"${flatpak_scan_json}"; then
    pass "CLI scan --flatpak discovers flatpak app"
else
    fail "CLI scan --flatpak missing org.gnome.calculator"
fi

if "${REGISTRY_BIN}" scan --all; then
    pass "CLI scan --all writes registry"
else
    fail "CLI scan --all failed"
fi

registry_list="$("${REGISTRY_BIN}" list 2>/dev/null || true)"
if grep -q 'demo-linux-app' <<<"${registry_list}" && grep -q 'org.gnome.calculator' <<<"${registry_list}"; then
    pass "registry lists scanned Linux + Flatpak apps"
else
    fail "registry missing scanned apps"
fi

scan_wrapper_json="$(
    STRAWWU_APP_REGISTRY_CLI="${REGISTRY_BIN}" \
    STRAWWU_LINUX_DESKTOP_DIRS="${STRAWWU_LINUX_DESKTOP_DIRS}" \
    STRAWWU_FLATPAK_LIST_FILE="${flatpak_fixture}" \
    STRAWWU_APP_REGISTRY="${STRAWWU_APP_REGISTRY}" \
    python3 "${SCAN_CLI}" --all --json 2>/dev/null || true
)"
if grep -q 'discovered' <<<"${scan_wrapper_json}"; then
    pass "strawwu-registry-scan wrapper integration"
else
    fail "strawwu-registry-scan wrapper integration"
fi

if STRAWWU_SKIP_REGISTRY_SCAN=1 bash "${APT_HOOK}"; then
    pass "APT hook honors STRAWWU_SKIP_REGISTRY_SCAN"
else
    fail "APT hook skip env broken"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-registry-hooks-baseline/v1",
    "wave": "W5-R4",
    "version": version,
    "package": "strawwu-registry-hooks",
    "registry_path": "/var/lib/strawwu/app-registry.json",
    "registry_cli": "/usr/bin/strawwu-app-registry",
    "scan_cli": "/usr/bin/strawwu-registry-scan",
    "apt_hook": "etc/apt/apt.conf.d/99strawwu-registry-hooks",
    "flatpak_trigger": "usr/share/flatpak/triggers/strawwu-registry-scan",
    "manifest": "os-image/debs/strawwu-registry-hooks/usr/share/strawwu/registry-hooks/registry-hooks-manifest.yaml",
    "scan_modes": ["linux", "flatpak"],
    "registry_commands": ["scan --linux", "scan --flatpak", "scan --all"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W5-R4 registry-hooks"

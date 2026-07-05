#!/usr/bin/env bash
# W5-D4: desktop context menu remove + favorites sync (strawwu-desktop-actions).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-desktop-actions"
DESKTOP_DIR="${REPO_ROOT}/os-image/debs/strawwu-desktop"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
COMPONENTS="${REPO_ROOT}/components"
CRATE_DIR="${COMPONENTS}/strawwu-app-registry"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-desktop-actions.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/context-menu-baseline.json"
MANIFEST="${DEB_DIR}/usr/share/strawwu/desktop-actions/desktop-actions-manifest.yaml"
NAUTILUS_SCRIPT="${DEB_DIR}/usr/share/nautilus/scripts/Remove from StrawWU"
REMOVE_CLI="${DEB_DIR}/usr/bin/strawwu-desktop-remove"
REGISTRY_BIN="${COMPONENTS}/target/debug/strawwu-app-registry"

echo "=== W5-D4 context-menu preflight ==="

require_plan "strawwu-app-registry-plan.md"
require_plan "strawwu-desktop-plan.md"

require_file "${DEB_DIR}/debian/control" "strawwu-desktop-actions debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-desktop-actions debian/postinst"
require_file "${BUILD}" "strawwu-desktop-actions build-deb.sh"
require_file "${MANIFEST}" "desktop-actions-manifest.yaml"
require_file "${REMOVE_CLI}" "strawwu-desktop-remove CLI"
require_file "${NAUTILUS_SCRIPT}" "Nautilus remove script"
require_file "${DEB_DIR}/usr/lib/strawwu-desktop-actions/core.py" "core.py"
require_file "${DEB_DIR}/usr/lib/strawwu-desktop-actions/desktop_parse.py" "desktop_parse.py"
require_file "${DEB_DIR}/usr/lib/strawwu-desktop-actions/favorites.py" "favorites.py"
require_file "${UNIT_TEST}" "desktop-actions unit test"

for script in "${BUILD}" "${REMOVE_CLI}" "${NAUTILUS_SCRIPT}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Package: strawwu-desktop-actions' "${DEB_DIR}/debian/control"; then
    pass "desktop-actions package name"
else
    fail "desktop-actions control missing package name"
fi

if grep -q 'strawwu-desktop-actions' "${DESKTOP_DIR}/debian/control"; then
    pass "strawwu-desktop Depends desktop-actions"
else
    fail "strawwu-desktop missing Depends: strawwu-desktop-actions"
fi

if grep -q 'strawwu-desktop-actions' "${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-desktop-actions"
else
    fail "target-manifest missing strawwu-desktop-actions"
fi

if grep -q 'schema: strawwu-desktop-actions-manifest/v1' "${MANIFEST}"; then
    pass "desktop-actions-manifest schema v1"
else
    fail "desktop-actions-manifest missing schema"
fi

if grep -q 'RemoveFromStrawWU' "${MANIFEST}" \
    && grep -q 'sync_on_remove: true' "${MANIFEST}"; then
    pass "manifest documents Desktop Action + favorites sync"
else
    fail "manifest missing Desktop Action or favorites sync"
fi

if grep -q 'strawwu-desktop-remove' "${NAUTILUS_SCRIPT}"; then
    pass "Nautilus script invokes strawwu-desktop-remove"
else
    fail "Nautilus script missing remove CLI"
fi

if grep -q 'remove-by-desktop' "${CRATE_DIR}/src/cli.rs" \
    && grep -q 'remove_by_desktop' "${CRATE_DIR}/src/registry.rs"; then
    pass "app-registry remove-by-desktop API"
else
    fail "app-registry missing remove-by-desktop"
fi

if grep -q 'test-context-menu:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-context-menu"
else
    fail "Makefile missing test-context-menu"
fi

if grep -q 'test-context-menu.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes context-menu"
else
    fail "preflight missing context-menu gate"
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
    pass "desktop-actions unit tests"
else
    fail "desktop-actions unit tests"
fi

if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "strawwu-desktop-actions build-deb.sh succeeded"
else
    fail "strawwu-desktop-actions build-deb.sh failed"
fi

deb="$(ls -1 "${OUTPUT_DIR}"/strawwu-desktop-actions_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb}" && -f "${deb}" ]]; then
    pass "desktop-actions deb artifact ${deb##*/}"
else
    fail "desktop-actions deb artifact missing"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"
export STRAWWU_APP_REGISTRY_CLI="${REGISTRY_BIN}"
export STRAWWU_SKIP_FAVORITES_SYNC=1

demo_desktop="${tmp_dir}/demo-app.desktop"
cat > "${demo_desktop}" <<EOF
[Desktop Entry]
Type=Application
Name=Demo App
Exec=/opt/demo/bin
X-StrawWU-App-Id=demo-app
EOF

if "${REGISTRY_BIN}" register --id demo-app --name "Demo App" --kind win32 --source manual \
    --desktop-entry "${demo_desktop}"; then
    pass "CLI register with desktop-entry"
else
    fail "CLI register with desktop-entry"
fi

if "${REGISTRY_BIN}" remove-by-desktop "${demo_desktop}" --dry-run --json | grep -q '"id": "demo-app"'; then
    pass "CLI remove-by-desktop dry-run"
else
    fail "CLI remove-by-desktop dry-run"
fi

if PYTHONPATH="${DEB_DIR}/usr/lib/strawwu-desktop-actions" \
    python3 - <<PY
import sys
from pathlib import Path
sys.path.insert(0, "${DEB_DIR}/usr/lib/strawwu-desktop-actions")
from desktop_parse import ensure_desktop_action, parse_app_id
p = Path("${demo_desktop}")
ensure_desktop_action(p, "demo-app")
assert parse_app_id(p) == "demo-app"
text = p.read_text(encoding="utf-8")
assert "RemoveFromStrawWU" in text
print("desktop action inject OK")
PY
then
    pass "Python inject Desktop Action"
else
    fail "Python inject Desktop Action"
fi

if PYTHONPATH="${DEB_DIR}/usr/lib/strawwu-desktop-actions" \
    STRAWWU_APP_REGISTRY="${STRAWWU_APP_REGISTRY}" \
    STRAWWU_APP_REGISTRY_CLI="${REGISTRY_BIN}" \
    STRAWWU_SKIP_FAVORITES_SYNC=1 \
    python3 "${REMOVE_CLI}" --desktop "${demo_desktop}" --dry-run | grep -q 'demo-app'; then
    pass "strawwu-desktop-remove dry-run integration"
else
    fail "strawwu-desktop-remove dry-run integration"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-desktop-context-menu-baseline/v1",
    "wave": "W5-D4",
    "version": version,
    "package": "strawwu-desktop-actions",
    "registry_path": "/var/lib/strawwu/app-registry.json",
    "registry_cli": "/usr/bin/strawwu-app-registry",
    "remove_cli": "/usr/bin/strawwu-desktop-remove",
    "nautilus_script": "/usr/share/nautilus/scripts/Remove from StrawWU",
    "desktop_action_id": "RemoveFromStrawWU",
    "favorites_schema": "org.gnome.shell",
    "favorites_key": "favorite-apps",
    "manifest": "os-image/debs/strawwu-desktop-actions/usr/share/strawwu/desktop-actions/desktop-actions-manifest.yaml",
    "i18n_keys": ["remove_label", "remove_confirm", "protected_error"],
    "registry_commands": ["remove-by-desktop", "register --desktop-entry"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W5-D4 context-menu"

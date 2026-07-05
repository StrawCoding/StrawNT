#!/usr/bin/env bash
# W4-D3: Hub settings center — elevate strawwu-hub to system settings.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HUB_DIR="${REPO_ROOT}/hub"
COMPONENTS_HUB="${REPO_ROOT}/components/strawwu-hub"
BASELINE="${BASELINES_DIR}/hub-settings-baseline.json"
LEGAL_DIR="${REPO_ROOT}/os-image/config/branding/usr/share/strawwu/legal"

echo "=== W4-D3 hub-settings preflight ==="

require_plan "strawwu-desktop-plan.md"
require_plan "strawwu-legal-compliance-plan.md"
require_plan "strawwu-windows-compat-integration-plan.md"

require_file "${HUB_DIR}/package.json" "hub package.json"
require_file "${HUB_DIR}/resources/settings-manifest.json" "settings manifest"
require_file "${HUB_DIR}/resources/strawwu-hub.desktop" "hub desktop file"
require_file "${HUB_DIR}/src/main/settings-service.js" "settings-service"
require_file "${HUB_DIR}/src/common/settings-paths.js" "settings-paths"
require_file "${HUB_DIR}/src/renderer/index.html" "hub renderer"
require_file "${HUB_DIR}/test/settings.test.js" "settings unit tests"

if [[ -L "${COMPONENTS_HUB}" || -d "${COMPONENTS_HUB}" ]]; then
    pass "components/strawwu-hub link or directory"
else
    fail "missing components/strawwu-hub (symlink to hub/)"
fi

for legal in privacy.html eula.html third-party.html; do
    if [[ -f "${LEGAL_DIR}/${legal}" ]]; then
        pass "legal doc ${legal}"
    else
        fail "missing legal doc ${legal}"
    fi
done

desktop="${HUB_DIR}/resources/strawwu-hub.desktop"
if grep -q 'Categories=Settings;System;' "${desktop}"; then
    pass "desktop Categories=Settings;System"
else
    fail "desktop missing Settings category"
fi

if grep -q 'Name=StrawWU Settings' "${desktop}"; then
    pass "desktop Name=StrawWU Settings"
else
    fail "desktop missing StrawWU Settings name"
fi

html="${HUB_DIR}/src/renderer/index.html"
for panel in tab-about tab-wincompat tab-system; do
    if grep -q "id=\"${panel}\"" "${html}"; then
        pass "renderer panel ${panel}"
    else
        fail "renderer missing ${panel}"
    fi
done

manifest="${HUB_DIR}/resources/settings-manifest.json"
if python3 - <<PY
import json, sys
data = json.load(open("${manifest}"))
assert data.get("role") == "system-settings-center"
assert "about" in {p["id"] for p in data.get("panels", [])}
assert "wincompat" in {p["id"] for p in data.get("panels", [])}
PY
then
    pass "settings manifest schema valid"
else
    fail "settings manifest invalid"
fi

if grep -q 'test-hub-settings:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-hub-settings"
else
    fail "Makefile missing test-hub-settings"
fi

if grep -q 'test-hub-settings.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes hub-settings"
else
    fail "preflight missing hub-settings gate"
fi

if [[ -f "${REPO_ROOT}/components/tests/wincompat/output/compat-matrix.json" ]]; then
    pass "dev compat-matrix.json present"
else
    fail "missing components/tests/wincompat/output/compat-matrix.json"
fi

if command -v node >/dev/null 2>&1; then
    if (cd "${HUB_DIR}" && npm test); then
        pass "hub npm test"
    else
        fail "hub npm test"
    fi
else
    fail "node not available for hub tests"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-hub-settings-baseline/v1",
    "wave": "W4-D3",
    "version": version,
    "package": "strawwu-hub",
    "role": "system-settings-center",
    "desktop_categories": ["Settings", "System"],
    "panels": [
        "status", "logs", "updates", "language",
        "wincompat", "system", "about",
    ],
    "legal_docs": [
        "/usr/share/strawwu/legal/privacy.html",
        "/usr/share/strawwu/legal/eula.html",
        "/usr/share/strawwu/legal/third-party.html",
    ],
    "bug_report_entry": "strawwu-bug-report-gtk",
    "compat_matrix_dev": "components/tests/wincompat/output/compat-matrix.json",
    "compat_matrix_installed": "/usr/share/strawwu/compat-matrix.json",
    "manifest": "hub/resources/settings-manifest.json",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W4-D3 hub-settings"

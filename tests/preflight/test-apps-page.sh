#!/usr/bin/env bash
# W4-R2: Hub Apps page — App Registry UI in strawwu-hub.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HUB_DIR="${REPO_ROOT}/hub"
COMPONENTS="${REPO_ROOT}/components"
CRATE_DIR="${COMPONENTS}/strawwu-app-registry"
FIXTURE="${CRATE_DIR}/tests/fixtures/sample-registry.json"
BASELINE="${BASELINES_DIR}/apps-page-baseline.json"
BIN="${COMPONENTS}/target/debug/strawwu-app-registry"

echo "=== W4-R2 apps-page preflight ==="

require_plan "strawwu-app-registry-plan.md"

require_file "${HUB_DIR}/src/main/app-registry-service.js" "app-registry-service"
require_file "${HUB_DIR}/resources/settings-manifest.json" "settings manifest"
require_file "${FIXTURE}" "sample-registry fixture"

manifest="${HUB_DIR}/resources/settings-manifest.json"
if python3 - <<PY
import json
data = json.load(open("${manifest}"))
assert "apps" in {p["id"] for p in data.get("panels", [])}
assert data.get("app_registry", {}).get("installed") == "/var/lib/strawwu/app-registry.json"
PY
then
    pass "settings manifest includes apps panel"
else
    fail "settings manifest missing apps panel"
fi

html="${HUB_DIR}/src/renderer/index.html"
for panel in tab-apps apps-list btn-refresh-apps; do
    if grep -q "id=\"${panel}\"" "${html}" || grep -q "${panel}" "${html}"; then
        pass "renderer includes ${panel}"
    else
        fail "renderer missing ${panel}"
    fi
done

if grep -q 'data-tab="apps"' "${html}"; then
    pass "sidebar nav apps tab"
else
    fail "sidebar missing apps nav"
fi

if grep -q 'GET_APPS' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC GET_APPS defined"
else
    fail "IPC GET_APPS missing"
fi

if grep -q 'test-apps-page:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-apps-page"
else
    fail "Makefile missing test-apps-page"
fi

if grep -q 'test-apps-page.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes apps-page"
else
    fail "preflight missing apps-page gate"
fi

if (cd "${COMPONENTS}" && cargo build --package strawwu-app-registry -q); then
    pass "cargo build strawwu-app-registry"
else
    fail "cargo build strawwu-app-registry"
fi

require_file "${BIN}" "strawwu-app-registry binary"

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
    "schema": "strawwu-hub-apps-page-baseline/v1",
    "wave": "W4-R2",
    "version": version,
    "package": "strawwu-hub",
    "panel": "apps",
    "registry_installed": "/var/lib/strawwu/app-registry.json",
    "registry_dev": "components/strawwu-app-registry/tests/fixtures/sample-registry.json",
    "registry_cli": "strawwu-app-registry",
    "registry_cli_dev": "components/target/debug/strawwu-app-registry",
    "ipc_channels": [
        "apps:get-list",
        "apps:preview-remove",
        "apps:remove",
    ],
    "manifest": "hub/resources/settings-manifest.json",
    "i18n_keys": ["nav.apps", "apps.title", "apps.remove"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W4-R2 apps-page"

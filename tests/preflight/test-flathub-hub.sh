#!/usr/bin/env bash
# W4-F3: Hub Flathub page — browse/install MVP in strawwu-hub.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HUB_DIR="${REPO_ROOT}/hub"
FIXTURE="${HUB_DIR}/tests/fixtures/flathub-catalog.json"
BASELINE="${BASELINES_DIR}/flathub-hub-baseline.json"

echo "=== W4-F3 flathub-hub preflight ==="

require_plan "strawwu-flathub-plan.md"

require_file "${HUB_DIR}/src/main/flathub-service.js" "flathub-service"
require_file "${HUB_DIR}/resources/settings-manifest.json" "settings manifest"
require_file "${FIXTURE}" "flathub catalog fixture"

manifest="${HUB_DIR}/resources/settings-manifest.json"
if python3 - <<PY
import json
data = json.load(open("${manifest}"))
assert "flathub" in {p["id"] for p in data.get("panels", [])}
assert data.get("flathub", {}).get("remote") == "flathub"
assert "flathub.org" in data.get("flathub", {}).get("api", "")
PY
then
    pass "settings manifest includes flathub panel"
else
    fail "settings manifest missing flathub panel"
fi

html="${HUB_DIR}/src/renderer/index.html"
for panel in tab-flathub flathub-list btn-refresh-flathub flathub-disclaimer; do
    if grep -q "${panel}" "${html}"; then
        pass "renderer includes ${panel}"
    else
        fail "renderer missing ${panel}"
    fi
done

if grep -q 'data-tab="flathub"' "${html}"; then
    pass "sidebar nav flathub tab"
else
    fail "sidebar missing flathub nav"
fi

if grep -q 'SEARCH_FLATHUB' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC SEARCH_FLATHUB defined"
else
    fail "IPC SEARCH_FLATHUB missing"
fi

if grep -q 'INSTALL_FLATHUB' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC INSTALL_FLATHUB defined"
else
    fail "IPC INSTALL_FLATHUB missing"
fi

if grep -q 'test-flathub-hub:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-flathub-hub"
else
    fail "Makefile missing test-flathub-hub"
fi

if grep -q 'test-flathub-hub.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes flathub-hub"
else
    fail "preflight missing flathub-hub gate"
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
    "schema": "strawwu-hub-flathub-baseline/v1",
    "wave": "W4-F3",
    "version": version,
    "package": "strawwu-hub",
    "panel": "flathub",
    "remote": "flathub",
    "api": "https://flathub.org/api/v2",
    "flatpak_cli": "/usr/bin/flatpak",
    "fixture": "hub/tests/fixtures/flathub-catalog.json",
    "ipc_channels": [
        "flathub:search",
        "flathub:get-status",
        "flathub:install",
    ],
    "manifest": "hub/resources/settings-manifest.json",
    "i18n_keys": ["nav.flathub", "flathub.title", "flathub.install", "flathub.disclaimer"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W4-F3 flathub-hub"

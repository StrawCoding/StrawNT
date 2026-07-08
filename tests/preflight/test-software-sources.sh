#!/usr/bin/env bash
# POST-D7: strawwu-software-sources preflight gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

SOURCES_DEB="${REPO_ROOT}/os-image/debs/strawwu-software-sources"
HUB_DIR="${REPO_ROOT}/hub"
BASELINE="${BASELINES_DIR}/software-sources-hub-baseline.json"

echo "=== POST-D7 strawwu-software-sources preflight ==="
require_plan "strawwu-d7-software-sources-plan.md"
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-D7-software-sources.md" "kickoff POST-D7"
require_file "${SOURCES_DEB}/DEBIAN/control" "strawwu-software-sources deb"
require_file "${SOURCES_DEB}/usr/bin/strawwu-software-sources" "strawwu-software-sources CLI"
require_file "${SOURCES_DEB}/usr/lib/strawwu-software-sources/core.py" "strawwu-software-sources core"
require_file "${SOURCES_DEB}/usr/share/strawwu/software-sources/software-sources-manifest.yaml" "software-sources manifest"
require_file "${SOURCES_DEB}/usr/share/strawwu/software-sources/fixture-catalog.json" "software-sources fixture"
require_file "${SOURCES_DEB}/usr/share/polkit-1/actions/xyz.wastebase.strawwu.software-sources.policy" "software-sources polkit"
require_file "${SOURCES_DEB}/usr/share/applications/strawwu-software-sources.desktop" "software-sources desktop"
require_file "${SOURCES_DEB}/build-deb.sh" "strawwu-software-sources build-deb.sh"
require_file "${REPO_ROOT}/os-image/scripts/build-os-debs.sh" "build-os-debs.sh"

TARGET_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
if grep -q 'strawwu-software-sources' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-software-sources"
else
    fail "target-manifest missing strawwu-software-sources"
fi

if grep -q 'strawwu-software-sources' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes strawwu-software-sources"
else
    fail "build-os-debs missing strawwu-software-sources"
fi

DESKTOP_CONTROL="${REPO_ROOT}/os-image/debs/strawwu-desktop/debian/control"
if grep -q 'strawwu-software-sources' "${DESKTOP_CONTROL}"; then
    pass "strawwu-desktop recommends strawwu-software-sources"
else
    fail "strawwu-desktop missing strawwu-software-sources"
fi

if grep -q 'strawwu-update-notifier' "${SOURCES_DEB}/DEBIAN/control"; then
    pass "software-sources depends on strawwu-update-notifier"
else
    fail "software-sources missing update-notifier dependency"
fi

OUTPUT_DIR="${SOURCES_DEB}/output"
if [[ -x "${SOURCES_DEB}/build-deb.sh" ]]; then
    STRAWWU_VERSION="${VERSION}" bash "${SOURCES_DEB}/build-deb.sh" >/dev/null
fi
deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-software-sources_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "strawwu-software-sources deb artifact"
else
    fail "strawwu-software-sources deb artifact missing"
fi

require_file "${HUB_DIR}/src/main/software-sources-service.js" "hub software-sources-service"
require_file "${HUB_DIR}/tests/fixtures/software-sources-catalog.json" "hub software-sources fixture"

if find "${HUB_DIR}" -iname '*software*source*' 2>/dev/null | grep -q .; then
    pass "Hub software-sources page artifact"
else
    fail "Hub software-sources page missing"
fi

html="${HUB_DIR}/src/renderer/index.html"
for panel in tab-software-sources sources-list btn-refresh-sources btn-check-updates sources-meta; do
    if grep -q "${panel}" "${html}"; then
        pass "renderer includes ${panel}"
    else
        fail "renderer missing ${panel}"
    fi
done

if grep -q 'data-tab="software-sources"' "${html}"; then
    pass "sidebar nav software-sources tab"
else
    fail "sidebar missing software-sources nav"
fi

manifest="${HUB_DIR}/resources/settings-manifest.json"
if python3 - <<PY
import json
data = json.load(open("${manifest}"))
assert "software-sources" in {p["id"] for p in data.get("panels", [])}
assert data.get("software_sources", {}).get("cli") == "/usr/bin/strawwu-software-sources"
assert data.get("software_sources", {}).get("update_notifier") == "strawwu-update-notifier"
PY
then
    pass "settings manifest includes software-sources panel"
else
    fail "settings manifest missing software-sources panel"
fi

if grep -q 'GET_SOFTWARE_SOURCES_STATUS' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC GET_SOFTWARE_SOURCES_STATUS defined"
else
    fail "IPC GET_SOFTWARE_SOURCES_STATUS missing"
fi

if grep -q 'CHECK_SOFTWARE_UPDATES' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC CHECK_SOFTWARE_UPDATES defined"
else
    fail "IPC CHECK_SOFTWARE_UPDATES missing"
fi

if python3 "${SOURCES_DEB}/tests/test-software-sources.py" -q; then
    pass "strawwu-software-sources python tests"
else
    fail "strawwu-software-sources python tests"
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
    "schema": "strawwu-software-sources-baseline/v1",
    "stage": "post-d7-software-sources",
    "version": version,
    "package": "strawwu-software-sources",
    "hub_panel": "software-sources",
    "cli": "/usr/bin/strawwu-software-sources",
    "polkit_action": "xyz.wastebase.strawwu.software-sources.toggle",
    "update_notifier": "strawwu-update-notifier",
    "readonly_sources": ["flathub", "ubuntu-security"],
    "strawwu_sources": ["strawwu-official"],
    "fixture": "os-image/debs/strawwu-software-sources/usr/share/strawwu/software-sources/fixture-catalog.json",
    "hub_fixture": "hub/tests/fixtures/software-sources-catalog.json",
    "ipc_channels": [
        "software-sources:get-status",
        "software-sources:toggle",
        "software-sources:check-updates",
    ],
    "i18n_keys": [
        "nav.software_sources",
        "sources.title",
        "sources.check_updates",
        "sources.readonly",
    ],
    "deferred": ["fork-suite-toggle"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "POST-D7 strawwu-software-sources"

#!/usr/bin/env bash
# POST-D1: strawwu-drivers preflight gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DRIVERS_DEB="${REPO_ROOT}/os-image/debs/strawwu-drivers"
HUB_DIR="${REPO_ROOT}/hub"
BASELINE="${BASELINES_DIR}/drivers-hub-baseline.json"

echo "=== POST-D1 strawwu-drivers preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-drivers-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-D1-strawwu-drivers.md" "kickoff POST-D1"
require_file "${DRIVERS_DEB}/DEBIAN/control" "strawwu-drivers deb"
require_file "${DRIVERS_DEB}/usr/bin/strawwu-drivers" "strawwu-drivers CLI"
require_file "${DRIVERS_DEB}/usr/lib/strawwu-drivers/core.py" "strawwu-drivers core"
require_file "${DRIVERS_DEB}/usr/share/strawwu/drivers/drivers-manifest.yaml" "drivers manifest"
require_file "${DRIVERS_DEB}/usr/share/strawwu/drivers/fixture-catalog.json" "drivers fixture"
require_file "${DRIVERS_DEB}/usr/share/polkit-1/actions/xyz.wastebase.strawwu.drivers.policy" "drivers polkit"
require_file "${DRIVERS_DEB}/build-deb.sh" "strawwu-drivers build-deb.sh"
require_file "${REPO_ROOT}/os-image/scripts/build-os-debs.sh" "build-os-debs.sh"

TARGET_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
if grep -q 'strawwu-drivers' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-drivers"
else
    fail "target-manifest missing strawwu-drivers"
fi

if grep -q 'strawwu-drivers' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes strawwu-drivers"
else
    fail "build-os-debs missing strawwu-drivers"
fi

DESKTOP_CONTROL="${REPO_ROOT}/os-image/debs/strawwu-desktop/debian/control"
if grep -q 'strawwu-drivers' "${DESKTOP_CONTROL}"; then
    pass "strawwu-desktop recommends strawwu-drivers"
else
    fail "strawwu-desktop missing strawwu-drivers"
fi

OUTPUT_DIR="${DRIVERS_DEB}/output"
if [[ -x "${DRIVERS_DEB}/build-deb.sh" ]]; then
    STRAWWU_VERSION="${VERSION}" bash "${DRIVERS_DEB}/build-deb.sh" >/dev/null
fi
deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-drivers_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "strawwu-drivers deb artifact"
else
    fail "strawwu-drivers deb artifact missing"
fi

require_file "${HUB_DIR}/src/main/drivers-service.js" "hub drivers-service"
require_file "${HUB_DIR}/tests/fixtures/drivers-catalog.json" "hub drivers fixture"

if find "${HUB_DIR}" -iname '*driver*' 2>/dev/null | grep -q .; then
    pass "Hub drivers page artifact"
else
    fail "Hub drivers page missing"
fi

html="${HUB_DIR}/src/renderer/index.html"
for panel in tab-drivers drivers-devices drivers-packages btn-refresh-drivers drivers-secure-boot; do
    if grep -q "${panel}" "${html}"; then
        pass "renderer includes ${panel}"
    else
        fail "renderer missing ${panel}"
    fi
done

if grep -q 'data-tab="drivers"' "${html}"; then
    pass "sidebar nav drivers tab"
else
    fail "sidebar missing drivers nav"
fi

manifest="${HUB_DIR}/resources/settings-manifest.json"
if python3 - <<PY
import json
data = json.load(open("${manifest}"))
assert "drivers" in {p["id"] for p in data.get("panels", [])}
assert data.get("drivers", {}).get("cli") == "/usr/bin/strawwu-drivers"
assert data.get("drivers", {}).get("secure_boot_plan") == "post-sec-secureboot-route"
PY
then
    pass "settings manifest includes drivers panel"
else
    fail "settings manifest missing drivers panel"
fi

if grep -q 'GET_DRIVERS_STATUS' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC GET_DRIVERS_STATUS defined"
else
    fail "IPC GET_DRIVERS_STATUS missing"
fi

if grep -q 'INSTALL_DRIVER' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC INSTALL_DRIVER defined"
else
    fail "IPC INSTALL_DRIVER missing"
fi

if python3 "${DRIVERS_DEB}/tests/test-drivers.py" -q; then
    pass "strawwu-drivers python tests"
else
    fail "strawwu-drivers python tests"
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
    "schema": "strawwu-drivers-baseline/v1",
    "stage": "post-d1-strawwu-drivers",
    "version": version,
    "package": "strawwu-drivers",
    "hub_panel": "drivers",
    "cli": "/usr/bin/strawwu-drivers",
    "polkit_action": "xyz.wastebase.strawwu.drivers.install",
    "secure_boot_plan": "post-sec-secureboot-route",
    "vendors": ["nvidia", "amd", "intel"],
    "fixture": "os-image/debs/strawwu-drivers/usr/share/strawwu/drivers/fixture-catalog.json",
    "hub_fixture": "hub/tests/fixtures/drivers-catalog.json",
    "ipc_channels": [
        "drivers:get-status",
        "drivers:list",
        "drivers:install",
    ],
    "i18n_keys": ["nav.drivers", "drivers.title", "drivers.install", "drivers.secure_boot_title"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "POST-D1 strawwu-drivers"

#!/usr/bin/env bash
# POST-DDP: device-proxy rootfs integration gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DDP_DEB="${REPO_ROOT}/os-image/debs/strawwu-device-proxy"
HUB_DIR="${REPO_ROOT}/hub"
CLI_DIR="${REPO_ROOT}/components/strawwu-cli"
COM_SMOKE="${REPO_ROOT}/tests/device-proxy/test-com-map-smoke.sh"
BASELINE="${BASELINES_DIR}/device-proxy-hub-baseline.json"

echo "=== POST-DDP rootfs preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-device-proxy-os-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-DDP-rootfs.md" "kickoff POST-DDP"
require_file "${REPO_ROOT}/components/specs/device-driver-proxy.md" "device-driver-proxy spec"

require_file "${CLI_DIR}/Cargo.toml" "strawwu-cli crate"
require_file "${CLI_DIR}/src/devices.rs" "strawwu-cli devices.rs"

if grep -rq "devices list" "${CLI_DIR}" 2>/dev/null; then
    pass "strawwu devices list"
else
    fail "strawwu devices list missing in strawwu-cli"
fi

if grep -q 'DevicesSubcommand' "${REPO_ROOT}/components/strawwu-launcher/src/cli.rs"; then
    pass "launcher parses devices subcommand"
else
    fail "launcher missing devices subcommand"
fi

require_file "${DDP_DEB}/DEBIAN/control" "strawwu-device-proxy deb"
require_file "${DDP_DEB}/usr/lib/udev/rules.d/99-strawwu-device-proxy.rules" "udev rules"
require_file "${DDP_DEB}/usr/lib/strawwu-device-proxy/hotplug-notify.sh" "hotplug notify script"
require_file "${DDP_DEB}/usr/share/strawwu/device-proxy/device-proxy-manifest.yaml" "device-proxy manifest"
require_file "${DDP_DEB}/usr/share/strawwu/device-proxy/fixture-catalog.json" "device-proxy fixture"
require_file "${DDP_DEB}/build-deb.sh" "strawwu-device-proxy build-deb.sh"

TARGET_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
if grep -q 'strawwu-device-proxy' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-device-proxy"
else
    fail "target-manifest missing strawwu-device-proxy"
fi

if grep -q 'strawwu-device-proxy' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes strawwu-device-proxy"
else
    fail "build-os-debs missing strawwu-device-proxy"
fi

DESKTOP_CONTROL="${REPO_ROOT}/os-image/debs/strawwu-desktop/debian/control"
if grep -q 'strawwu-device-proxy' "${DESKTOP_CONTROL}"; then
    pass "strawwu-desktop recommends strawwu-device-proxy"
else
    fail "strawwu-desktop missing strawwu-device-proxy"
fi

if [[ -x "${DDP_DEB}/build-deb.sh" ]]; then
    STRAWWU_VERSION="${VERSION}" bash "${DDP_DEB}/build-deb.sh" >/dev/null
fi
deb_file="$(ls -1 "${DDP_DEB}/output"/strawwu-device-proxy_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "strawwu-device-proxy deb artifact"
else
    fail "strawwu-device-proxy deb artifact missing"
fi

if python3 "${DDP_DEB}/tests/test-device-proxy-os.py" -q; then
    pass "strawwu-device-proxy python tests"
else
    fail "strawwu-device-proxy python tests"
fi

require_file "${HUB_DIR}/src/main/device-proxy-service.js" "hub device-proxy-service"
require_file "${HUB_DIR}/tests/fixtures/device-proxy-catalog.json" "hub device-proxy fixture"

if find -L "${REPO_ROOT}/components/strawwu-hub" -iname '*device*' 2>/dev/null | grep -q .; then
    pass "Hub devices page artifact"
else
    fail "Hub devices page missing"
fi

html="${HUB_DIR}/src/renderer/index.html"
for panel in tab-devices devices-list devices-tier-summary btn-refresh-devices devices-hotplug-status; do
    if grep -q "${panel}" "${html}"; then
        pass "renderer includes ${panel}"
    else
        fail "renderer missing ${panel}"
    fi
done

if grep -q 'data-tab="devices"' "${html}"; then
    pass "sidebar nav devices tab"
else
    fail "sidebar missing devices nav"
fi

manifest="${HUB_DIR}/resources/settings-manifest.json"
if python3 - <<PY
import json
data = json.load(open("${manifest}"))
assert "devices" in {p["id"] for p in data.get("panels", [])}
assert data.get("device_proxy", {}).get("cli") == "/usr/bin/strawwu"
assert data.get("device_proxy", {}).get("list_command") == "devices list --json"
PY
then
    pass "settings manifest includes devices panel"
else
    fail "settings manifest missing devices panel"
fi

if grep -q 'GET_DEVICE_PROXY_STATUS' "${HUB_DIR}/src/common/constants.js"; then
    pass "IPC GET_DEVICE_PROXY_STATUS defined"
else
    fail "IPC GET_DEVICE_PROXY_STATUS missing"
fi

if (cd "${REPO_ROOT}/components" && cargo test --package strawwu-cli -q); then
    pass "cargo test strawwu-cli"
else
    fail "cargo test strawwu-cli"
fi

if (cd "${REPO_ROOT}/components" && cargo build --bin strawwu -q); then
    pass "cargo build strawwu binary"
else
    fail "cargo build strawwu binary"
fi

STRAWWU_BIN="${REPO_ROOT}/components/target/debug/strawwu"
if "${STRAWWU_BIN}" devices list | grep -q 'Serial/COM'; then
    pass "strawwu devices list CLI smoke"
else
    fail "strawwu devices list CLI smoke"
fi

if [[ -x "${COM_SMOKE}" ]]; then
    if bash "${COM_SMOKE}"; then
        pass "DDP3 COM mapping smoke"
    else
        fail "DDP3 COM mapping smoke"
    fi
else
    fail "COM smoke script not executable"
fi

if (cd "${HUB_DIR}" && npm test --silent 2>/dev/null); then
    pass "hub npm test"
else
    fail "hub npm test"
fi

mkdir -p "${BASELINES_DIR}"
python3 - <<PY
import json
from pathlib import Path
baseline = {
    "schema": "strawwu-hub-device-proxy-baseline/v1",
    "stage": "post-ddp-rootfs",
    "version": "${VERSION}",
    "package": "strawwu-hub",
    "cli": "strawwu devices list",
    "udev_rules": "99-strawwu-device-proxy.rules",
    "hub_panel": "devices",
}
Path("${BASELINE}").write_text(json.dumps(baseline, indent=2) + "\\n")
print("baseline written")
PY
pass "device-proxy-hub baseline"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "=== POST-DDP rootfs done: PASS ==="

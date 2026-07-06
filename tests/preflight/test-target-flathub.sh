#!/usr/bin/env bash
# W6-F5: target Flathub E2E — installed system flathub system remote after Calamares.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

E2E_DIR="${REPO_ROOT}/tests/install-e2e"
RUNNER="${E2E_DIR}/run-target-flathub.sh"
LIB="${E2E_DIR}/lib.sh"
MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
BASELINE="${BASELINES_DIR}/target-flathub-baseline.json"

echo "=== W6-F5 target-flathub preflight ==="

require_plan "strawwu-flathub-plan.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${RUNNER}" "run-target-flathub.sh"
require_file "${LIB}" "install-e2e lib.sh"
require_file "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/debian/postinst" "flatpak-setup postinst"

if [[ -x "${RUNNER}" ]]; then
    pass "run-target-flathub.sh executable"
else
    chmod +x "${RUNNER}"
    pass "chmod +x run-target-flathub.sh"
fi

if grep -q 'MARKER_FLATHUB.*TARGET_FLATHUB_OK' "${LIB}" \
    && grep -q 'check_flathub_remote_in_root' "${LIB}" \
    && grep -q 'mount_installed_root' "${LIB}" \
    && grep -q 'inject_flathub_e2e_service' "${LIB}"; then
    pass "lib.sh target flathub helpers (mount + remote check + boot probe)"
else
    fail "lib.sh missing target flathub helpers"
fi

if grep -q 'flatpak remote-add --if-not-exists --system flathub' \
    "${REPO_ROOT}/os-image/debs/strawwu-flatpak-setup/debian/postinst"; then
    pass "flatpak-setup postinst registers flathub system remote"
else
    fail "flatpak-setup postinst missing flathub remote-add"
fi

if grep -q 'strawwu-flatpak-setup' "${MANIFEST}"; then
    pass "target-manifest includes strawwu-flatpak-setup"
else
    fail "target-manifest missing strawwu-flatpak-setup"
fi

if grep -q 'run_filesystem_probe' "${RUNNER}" \
    && grep -q 'run_boot_probe' "${RUNNER}" \
    && grep -q 'MARKER_FLATHUB' "${RUNNER}"; then
    pass "runner verifies filesystem + boot flathub remote"
else
    fail "runner missing filesystem/boot flathub probes"
fi

if grep -q 'test-target-flathub' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-target-flathub target"
else
    fail "Makefile missing test-target-flathub"
fi

if grep -q 'test-target-flathub.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes target-flathub"
else
    fail "Makefile preflight missing test-target-flathub.sh"
fi

baseline_content="$(python3 - <<PY
import json
data = {
    "schema": "strawwu-target-flathub-baseline/v1",
    "wave": "W6-F5",
    "version": "${VERSION}",
    "flathub_marker": "TARGET_FLATHUB_OK",
    "runner": "tests/install-e2e/run-target-flathub.sh",
    "result_json": "tests/install-e2e/output/target-flathub-result.json",
    "remote": "flathub",
    "remote_url": "https://dl.flathub.org/repo/",
    "package": "strawwu-flatpak-setup",
    "depends_on": ["validate-calamares-preflight", "validate-partition-probe"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W6-F5 target-flathub"

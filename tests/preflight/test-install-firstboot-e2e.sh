#!/usr/bin/env bash
# W6-N5: install + firstboot E2E — serial FIRSTBOOT_OK after Calamares install.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

E2E_DIR="${REPO_ROOT}/tests/install-e2e"
DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-firstboot"
RUNNER="${E2E_DIR}/run-firstboot-e2e.sh"
OVERLAY_SYNC="${E2E_DIR}/sync-firstboot-overlay.sh"
BOOT_SETUP="${E2E_DIR}/guest/e2e-bootloader-setup.sh"
CORE="${DEB_DIR}/usr/lib/strawwu-firstboot/core.py"
CLI="${DEB_DIR}/usr/bin/strawwu-firstboot"
UNIT_TEST="${DEB_DIR}/tests/test-firstboot.py"
BASELINE="${BASELINES_DIR}/install-firstboot-e2e-baseline.json"

echo "=== W6-N5 install-firstboot-e2e preflight ==="

require_plan "strawwu-install-init-plan.md"
require_plan "strawwu-observability-debug-plan.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${RUNNER}" "run-firstboot-e2e.sh"
require_file "${OVERLAY_SYNC}" "sync-firstboot-overlay.sh"
require_file "${BOOT_SETUP}" "e2e-bootloader-setup.sh"
require_file "${E2E_DIR}/lib.sh" "install-e2e lib.sh"
require_file "${CORE}" "firstboot core.py"
require_file "${CLI}" "strawwu-firstboot CLI"
require_file "${UNIT_TEST}" "firstboot unit tests"

for script in "${RUNNER}" "${OVERLAY_SYNC}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'MARKER_FIRSTBOOT.*FIRSTBOOT_OK' "${E2E_DIR}/lib.sh"; then
    pass "lib.sh MARKER_FIRSTBOOT=FIRSTBOOT_OK"
else
    fail "lib.sh missing MARKER_FIRSTBOOT"
fi

if grep -q 'shellprocess_e2e-locale.conf' "${E2E_DIR}/guest/settings.conf" \
    && [[ -f "${E2E_DIR}/guest/shellprocess_e2e-locale.conf" ]]; then
    pass "e2e settings use fast locale shellprocess (no localecfg hang)"
else
    fail "e2e settings missing e2e_locale shellprocess"
fi

if grep -q 'strawwu-firstboot-e2e.service' "${BOOT_SETUP}" \
    && grep -q 'run --e2e' "${BOOT_SETUP}" \
    && grep -q 'firstboot-e2e-overlay' "${BOOT_SETUP}"; then
    pass "e2e-bootloader-setup installs firstboot E2E service + overlay"
else
    fail "e2e-bootloader-setup missing firstboot E2E wiring"
fi

if grep -q 'def run_e2e' "${CORE}" && grep -q 'E2E_MARKER = "FIRSTBOOT_OK"' "${CORE}"; then
    pass "core.py run_e2e + FIRSTBOOT_OK constant"
else
    fail "core.py missing run_e2e or E2E_MARKER"
fi

if grep -q '\-\-e2e' "${CLI}" && grep -q 'run_e2e' "${CLI}"; then
    pass "CLI --e2e wired to run_e2e"
else
    fail "CLI missing --e2e wiring"
fi

if grep -q 'test_run_e2e_writes_state' "${UNIT_TEST}"; then
    pass "unit test covers run_e2e"
else
    fail "unit test missing run_e2e coverage"
fi

if grep -q 'test-install-firstboot-e2e' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-install-firstboot-e2e target"
else
    fail "Makefile missing test-install-firstboot-e2e"
fi

if grep -q 'test-install-firstboot-e2e.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes install-firstboot-e2e"
else
    fail "Makefile preflight missing test-install-firstboot-e2e.sh"
fi

echo "=== firstboot unit tests (E2E mode) ==="
python3 "${UNIT_TEST}" -v

baseline_content="$(python3 - <<PY
import json
data = {
    "schema": "strawwu-install-firstboot-e2e-baseline/v1",
    "wave": "W6-N5",
    "version": "${VERSION}",
    "firstboot_marker": "FIRSTBOOT_OK",
    "runner": "tests/install-e2e/run-firstboot-e2e.sh",
    "overlay_sync": "tests/install-e2e/sync-firstboot-overlay.sh",
    "result_json": "tests/install-e2e/output/firstboot-e2e-result.json",
    "boot_service": "strawwu-firstboot-e2e.service",
    "cli_flag": "--e2e",
    "depends_on": ["validate-calamares-preflight", "validate-partition-probe"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W6-N5 install-firstboot-e2e"

#!/usr/bin/env bash
# W6-I4: installed boot E2E — Calamares install → BIOS + UEFI STRAWWU_BOOT_OK.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

E2E_DIR="${REPO_ROOT}/tests/install-e2e"
RUNNER="${E2E_DIR}/run-installed-boot.sh"
BOOT_SETUP="${E2E_DIR}/guest/e2e-bootloader-setup.sh"
LIB="${E2E_DIR}/lib.sh"
BASELINE="${BASELINES_DIR}/installed-boot-baseline.json"

echo "=== W6-I4 installed-boot preflight ==="

require_plan "strawwu-installer-plan.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${RUNNER}" "run-installed-boot.sh"
require_file "${BOOT_SETUP}" "e2e-bootloader-setup.sh"
require_file "${LIB}" "install-e2e lib.sh"
require_file "${E2E_DIR}/guest/modules/partition/main.py" "partition python module"

if [[ -x "${RUNNER}" ]]; then
    pass "run-installed-boot.sh executable"
else
    chmod +x "${RUNNER}"
    pass "chmod +x run-installed-boot.sh"
fi

if grep -q 'run_installed_disk_boot' "${LIB}" \
    && grep -q 'find_ovmf_code' "${LIB}"; then
    pass "lib.sh installed-disk boot helpers (bios + uefi)"
else
    fail "lib.sh missing run_installed_disk_boot / OVMF helpers"
fi

if grep -q 'EFI/BOOT/grub.cfg' "${BOOT_SETUP}" \
    && grep -q 'BOOTX64.EFI' "${BOOT_SETUP}" \
    && grep -q 'i386-pc' "${BOOT_SETUP}"; then
    pass "e2e-bootloader-setup installs BIOS MBR + UEFI ESP (fallback grub.cfg)"
else
    fail "e2e-bootloader-setup missing dual bootloader install"
fi

if grep -q 'ef00' "${E2E_DIR}/guest/modules/partition/main.py" \
    && grep -q '/boot/efi' "${E2E_DIR}/guest/modules/partition/main.py"; then
    pass "partition module creates ESP + root (UEFI installed boot)"
else
    fail "partition module missing EFI System Partition"
fi

if grep -q 'test-installed-boot' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-installed-boot target"
else
    fail "Makefile missing test-installed-boot"
fi

if grep -q 'test-installed-boot.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes installed-boot"
else
    fail "Makefile preflight missing test-installed-boot.sh"
fi

if grep -q 'run_dual_boot_phase' "${RUNNER}" \
    && grep -q 'modes_tested.*bios.*uefi' "${RUNNER}"; then
    pass "runner tests BIOS + UEFI installed boot"
else
    fail "runner missing dual boot phase"
fi

baseline_content="$(python3 - <<PY
import json
data = {
    "schema": "strawwu-installed-boot-baseline/v1",
    "wave": "W6-I4",
    "version": "${VERSION}",
    "boot_marker": "STRAWWU_BOOT_OK",
    "runner": "tests/install-e2e/run-installed-boot.sh",
    "result_json": "tests/install-e2e/output/installed-boot-result.json",
    "modes": ["bios", "uefi"],
    "depends_on": ["validate-calamares-preflight", "validate-partition-probe"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W6-I4 installed-boot"

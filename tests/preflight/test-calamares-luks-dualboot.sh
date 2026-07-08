#!/usr/bin/env bash
# POST-I2: Calamares LUKS + dual-boot verification gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
BUILD="${DEB_DIR}/build-deb.sh"
SCEN_VALIDATE="${REPO_ROOT}/tests/install-e2e/validate-luks-dualboot-scenarios.sh"
UNIT_TEST="${DEB_DIR}/tests/test-luks-dualboot.py"
BASELINE="${BASELINES_DIR}/calamares-luks-dualboot-baseline.json"

echo "=== POST-I2 calamares LUKS/dualboot preflight ==="
require_plan "strawwu-installer-advanced-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-I2-calamares-luks.md" "kickoff POST-I2"
require_file "${DEB_DIR}/debian/control" "debian/control"

PARTITION="${DEB_DIR}/etc/calamares/modules/partition.conf"
GRUBCFG="${DEB_DIR}/etc/calamares/modules/grubcfg.conf"
FSTAB="${DEB_DIR}/etc/calamares/modules/fstab.conf"
WELCOME="${DEB_DIR}/etc/calamares/modules/welcome.conf"
DUALBOOT_SH="${DEB_DIR}/usr/local/lib/calamares/strawwu-dualboot-detect.sh"
SETTINGS="${DEB_DIR}/etc/calamares/settings.conf"

require_file "${PARTITION}" "partition.conf"
require_file "${GRUBCFG}" "grubcfg.conf"
require_file "${FSTAB}" "fstab.conf"
require_file "${WELCOME}" "welcome.conf"
require_file "${DUALBOOT_SH}" "strawwu-dualboot-detect.sh"
require_file "${SCEN_VALIDATE}" "validate-luks-dualboot-scenarios.sh"
require_file "${REPO_ROOT}/tests/install-e2e/scenarios/luks-scenario.marker.json" "luks scenario marker"
require_file "${REPO_ROOT}/tests/install-e2e/scenarios/dualboot-scenario.marker.json" "dualboot scenario marker"

if grep -qE 'luksGeneration:[[:space:]]*luks1' "${PARTITION}" \
    && grep -q 'enableLuksAutomatedPartitioning: true' "${PARTITION}"; then
    pass "partition.conf LUKS automated encryption (C7)"
else
    fail "partition.conf missing LUKS settings"
fi

if grep -q 'initialPartitioningChoice: none' "${PARTITION}"; then
    pass "partition.conf dual-boot choice page (no pre-selected erase)"
else
    fail "partition.conf must use initialPartitioningChoice: none for dual-boot UX"
fi

if grep -q 'GRUB_ENABLE_CRYPTODISK: true' "${GRUBCFG}" \
    && grep -q 'GRUB_DISABLE_OS_PROBER: false' "${GRUBCFG}"; then
    pass "grubcfg cryptodisk + os-prober enabled (C7/C8)"
else
    fail "grubcfg.conf missing LUKS/dualboot GRUB defaults"
fi

if grep -q 'crypttabOptions: luks' "${FSTAB}"; then
    pass "fstab crypttab LUKS options"
else
    fail "fstab.conf missing crypttabOptions luks"
fi

if grep -q 'requiredStorage:' "${WELCOME}" && grep -q 'storage' "${WELCOME}"; then
    pass "welcome.conf storage requirement for alongside/replace"
else
    fail "welcome.conf missing requiredStorage for dual-boot paths"
fi

if grep -q 'dualboot_detect' "${SETTINGS}" && grep -q 'shellprocess@dualboot_detect' "${SETTINGS}"; then
    pass "settings.conf dualboot_detect shellprocess wired"
else
    fail "settings.conf missing dualboot_detect exec step"
fi

if [[ -x "${DUALBOOT_SH}" ]]; then
    pass "dualboot detect script executable"
else
    chmod +x "${DUALBOOT_SH}"
    pass "chmod +x strawwu-dualboot-detect.sh"
fi

bash -n "${DUALBOOT_SH}" && pass "dualboot detect script syntax"

if grep -q 'test-calamares-luks-dualboot' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-calamares-luks-dualboot target"
else
    fail "Makefile missing test-calamares-luks-dualboot"
fi

chmod +x "${SCEN_VALIDATE}" 2>/dev/null || true
if bash "${SCEN_VALIDATE}"; then
    pass "install-e2e LUKS/dualboot scenario markers"
else
    fail "install-e2e scenario validation failed"
fi

if python3 "${UNIT_TEST}"; then
    pass "strawwu-calamares-settings luks-dualboot unit tests"
else
    fail "strawwu-calamares-settings luks-dualboot unit tests"
fi

rm -rf "${DEB_DIR}/output"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${DEB_DIR}/output"/strawwu-calamares-settings_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
    listing="$(dpkg-deb -c "${deb_file}")"
    for rel in \
        ./etc/calamares/modules/partition.conf \
        ./etc/calamares/modules/grubcfg.conf \
        ./etc/calamares/modules/shellprocess_dualboot-detect.conf \
        ./usr/local/lib/calamares/strawwu-dualboot-detect.sh; do
        if grep -qF "${rel}" <<< "${listing}"; then
            pass "deb contains ${rel#./}"
        else
            fail "deb missing ${rel#./}"
        fi
    done
else
    fail "deb artifact missing for VERSION ${VERSION}"
fi

baseline_content="$(python3 - "${BASELINE}" "${VERSION}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
data = {
    "schema": "strawwu-calamares-luks-dualboot-baseline/v1",
    "stage": "post-i2-calamares-luks",
    "version": version,
    "preflight": "tests/preflight/test-calamares-luks-dualboot.sh",
    "scenario_validate": "tests/install-e2e/validate-luks-dualboot-scenarios.sh",
    "unit_test": "os-image/debs/strawwu-calamares-settings/tests/test-luks-dualboot.py",
    "scenarios": [
        "tests/install-e2e/scenarios/luks-scenario.marker.json",
        "tests/install-e2e/scenarios/dualboot-scenario.marker.json",
    ],
    "markers": {
        "luks": "STRAWWU-LUKS-SCENARIO-OK",
        "dualboot": "STRAWWU-DUALBOOT-SCENARIO-OK",
    },
    "calamares_refs": {
        "partition": "os-image/debs/strawwu-calamares-settings/etc/calamares/modules/partition.conf",
        "grubcfg": "os-image/debs/strawwu-calamares-settings/etc/calamares/modules/grubcfg.conf",
        "dualboot_detect": "os-image/debs/strawwu-calamares-settings/usr/local/lib/calamares/strawwu-dualboot-detect.sh",
    },
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "POST-I2 calamares LUKS/dualboot"

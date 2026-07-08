#!/usr/bin/env bash
# Validate POST-I2 LUKS + dualboot install-e2e scenario markers (static gate).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCEN_DIR="${REPO_ROOT}/tests/install-e2e/scenarios"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

for id in luks dualboot; do
    f="${SCEN_DIR}/${id}-scenario.marker.json"
    [[ -f "${f}" ]] || fail "missing scenario ${f}"
    python3 -m json.tool "${f}" >/dev/null || fail "invalid JSON ${f}"
    pass "scenario marker ${id}"
done

luks_marker="$(python3 -c "import json; print(json.load(open('${SCEN_DIR}/luks-scenario.marker.json'))['marker'])")"
dual_marker="$(python3 -c "import json; print(json.load(open('${SCEN_DIR}/dualboot-scenario.marker.json'))['marker'])")"

grep -q 'luksGeneration' "${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/etc/calamares/modules/partition.conf" \
    || fail "partition.conf missing luksGeneration"
grep -q 'enableLuksAutomatedPartitioning' "${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/etc/calamares/modules/partition.conf" \
    || fail "partition.conf missing enableLuksAutomatedPartitioning"
grep -q 'GRUB_ENABLE_CRYPTODISK' "${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/etc/calamares/modules/grubcfg.conf" \
    || fail "grubcfg.conf missing GRUB_ENABLE_CRYPTODISK"
grep -q 'GRUB_DISABLE_OS_PROBER: false' "${REPO_ROOT}/os-image/debs/strawwu-calamares-settings/etc/calamares/modules/grubcfg.conf" \
    || fail "grubcfg.conf must enable os-prober for dualboot"

pass "luks scenario config refs (${luks_marker})"
pass "dualboot scenario config refs (${dual_marker})"
echo "ALL SCENARIO CHECKS PASS"

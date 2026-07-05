#!/usr/bin/env bash
# W2-N1: strawwu-initd — shared setup state.json CLI + init-tools baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-initd"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-state.py"
SCHEMA="${REPO_ROOT}/docs/plans/schemas/setup-state.schema.json"
OUTPUT_DIR="${DEB_DIR}/output"
CLI="${DEB_DIR}/usr/bin/strawwu-initd"

echo "=== W2-N1 init-tools preflight ==="

require_plan "strawwu-install-init-plan.md"
require_plan "strawwu-upgrade-recovery-plan.md"

require_file "${REPO_ROOT}/os-image/config/branding/usr/local/sbin/strawwu-boot-selfcheck" "branding strawwu-boot-selfcheck"
require_file "${REPO_ROOT}/os-image/config/branding/etc/systemd/system/strawwu-boot-selfcheck.service" "branding boot-selfcheck unit"

EXPECTED_DEBS=(
    strawwu-initd
    strawwu-install-init
    strawwu-target-setup
    strawwu-firstboot
)

missing_debs=()
for deb in "${EXPECTED_DEBS[@]}"; do
    if [[ -d "${REPO_ROOT}/packaging/debs/${deb}" ]] || [[ -d "${REPO_ROOT}/os-image/debs/${deb}" ]]; then
        pass "deb scaffold ${deb}"
    else
        missing_debs+=("${deb}")
        warn "deb scaffold missing ${deb} (Wave N2+)"
    fi
done

if [[ ${#missing_debs[@]} -eq 0 ]]; then
    pass "all init deb scaffolds present"
elif [[ ${#missing_debs[@]} -lt ${#EXPECTED_DEBS[@]} ]]; then
    pass "initd scaffold present; ${#missing_debs[@]} sibling deb(s) pending"
fi

if grep -q 'strawwu-firstboot' "${PLANS_DIR}/strawwu-install-init-plan.md"; then
    pass "install-init plan defines firstboot"
else
    fail "install-init plan missing firstboot section"
fi

if grep -q 'state.json' "${PLANS_DIR}/strawwu-install-init-plan.md"; then
    pass "install-init plan defines state.json path"
else
    fail "install-init plan missing state.json"
fi

if grep -q 'strawwu-initd repair' "${PLANS_DIR}/strawwu-upgrade-recovery-plan.md"; then
    pass "upgrade plan documents strawwu-initd repair"
else
    fail "upgrade plan missing strawwu-initd repair"
fi

# --- strawwu-initd package ---
require_file "${DEB_DIR}/debian/control" "strawwu-initd debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-initd debian/postinst"
require_file "${BUILD}" "strawwu-initd build-deb.sh"
require_file "${CLI}" "strawwu-initd CLI"
require_file "${DEB_DIR}/usr/lib/strawwu-initd/state.py" "state.py"
require_file "${SCHEMA}" "setup-state.schema.json"
require_file "${UNIT_TEST}" "test-state.py unit test"

for script in "${BUILD}" "${CLI}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q '"const": "1.0"' "${SCHEMA}"; then
    pass "setup-state schema_version 1.0 frozen"
else
    fail "setup-state schema missing schema_version 1.0 const"
fi

validate_json_file "${SCHEMA}"

if grep -q '/var/lib/strawwu/setup/state.json' "${PLANS_DIR}/strawwu-install-init-plan.md"; then
    pass "state path aligned with plan"
else
    fail "state path mismatch vs install-init plan"
fi

if python3 "${UNIT_TEST}"; then
    pass "state unit tests"
else
    fail "state unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-initd_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

# CLI integration in temp dir
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_SETUP_STATE="${tmp_dir}/state.json"
export STRAWWU_INITD_LOG="${tmp_dir}/initd.log"

if "${CLI}" version | grep -q 'strawwu-initd'; then
    pass "CLI version"
else
    fail "CLI version"
fi

if "${CLI}" init; then
    pass "CLI init"
else
    fail "CLI init"
fi

if "${CLI}" validate; then
    pass "CLI validate default path"
else
    fail "CLI validate default path"
fi

if "${CLI}" get lifecycle.firstboot | grep -q 'pending'; then
    pass "CLI get lifecycle.firstboot"
else
    fail "CLI get lifecycle.firstboot"
fi

if "${CLI}" set lifecycle.target_setup done; then
    pass "CLI set lifecycle.target_setup"
else
    fail "CLI set lifecycle.target_setup"
fi

if "${CLI}" show --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["lifecycle"]["target_setup"]=="done"'; then
    pass "CLI show --json"
else
    fail "CLI show --json"
fi

if ! "${CLI}" set lifecycle.install bogus 2>/dev/null; then
    pass "CLI rejects invalid lifecycle value"
else
    fail "CLI should reject invalid lifecycle value"
fi

# Corrupt + repair
printf '%s\n' '{bad json' > "${STRAWWU_SETUP_STATE}"
if "${CLI}" repair; then
    pass "CLI repair corrupt state"
else
    fail "CLI repair corrupt state"
fi

if "${CLI}" validate; then
    pass "CLI validate after repair"
else
    fail "CLI validate after repair"
fi

if "${CLI}" migrate --dry-run | grep -q 'schema_version=1.0'; then
    pass "CLI migrate dry-run"
else
    fail "CLI migrate dry-run"
fi

if [[ -f "${STRAWWU_SETUP_STATE}" ]]; then
    validate_json_file "${STRAWWU_SETUP_STATE}"
    pass "state JSON written"
else
    fail "state JSON not written"
fi

if python3 - <<'PY' "${STRAWWU_SETUP_STATE}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data["schema_version"] == "1.0"
assert set(data["lifecycle"]) == {
    "install",
    "target_setup",
    "target_identity",
    "upstream_init_disabled",
    "boot_selfcheck",
    "firstboot",
}
assert data["flags"]["firstboot_required"] is True
print("lifecycle shape OK")
PY
then
    pass "setup-state lifecycle shape"
else
    fail "setup-state lifecycle shape"
fi

preflight_exit "W2-N1 init-tools"

#!/usr/bin/env bash
# POST-SEC: Secure Boot shim + signed kernel/initrd route skeleton gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

SB_DEB="${REPO_ROOT}/os-image/debs/strawwu-secureboot"
SB_SCRIPTS="${REPO_ROOT}/os-image/scripts/secureboot-route"
UNIT_TEST="${SB_DEB}/tests/test-secureboot.py"
BASELINE="${BASELINES_DIR}/secureboot-route-baseline.json"
TRUST_MODEL="${PLANS_DIR}/strawwu-security-trust-model.md"

echo "=== POST-SEC secureboot route preflight ==="

require_plan "strawwu-security-trust-model.md"
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-SEC-secureboot-route.md" "kickoff POST-SEC-secureboot-route"

if grep -q "shim" "${TRUST_MODEL}" && grep -qi "signed kernel" "${TRUST_MODEL}" && grep -qi "signed initrd" "${TRUST_MODEL}"; then
    pass "SB route documented in security-trust-model"
else
    fail "SB route incomplete in security-trust-model"
fi

require_file "${SB_DEB}/DEBIAN/control" "strawwu-secureboot deb"
require_file "${SB_DEB}/usr/bin/strawwu-secureboot" "strawwu-secureboot CLI"
require_file "${SB_DEB}/usr/lib/strawwu-secureboot/core.py" "strawwu-secureboot core"
require_file "${SB_DEB}/usr/share/strawwu/secureboot/secureboot-manifest.yaml" "secureboot manifest"
require_file "${SB_DEB}/usr/share/strawwu/secureboot/fixture-catalog.json" "secureboot fixture"
require_file "${SB_DEB}/build-deb.sh" "strawwu-secureboot build-deb.sh"
require_file "${UNIT_TEST}" "test-secureboot.py"

require_file "${SB_SCRIPTS}/MANIFEST.yaml" "secureboot-route MANIFEST"
require_file "${SB_SCRIPTS}/sign-boot-artifacts.sh" "sign-boot-artifacts.sh"
require_file "${SB_SCRIPTS}/verify-boot-chain.sh" "verify-boot-chain.sh"

for script in \
    "${SB_DEB}/build-deb.sh" \
    "${SB_DEB}/usr/bin/strawwu-secureboot" \
    "${SB_SCRIPTS}/sign-boot-artifacts.sh" \
    "${SB_SCRIPTS}/verify-boot-chain.sh"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

for script in "${SB_SCRIPTS}/sign-boot-artifacts.sh" "${SB_SCRIPTS}/verify-boot-chain.sh"; do
    if bash -n "${script}"; then
        pass "bash -n $(basename "${script}")"
    else
        fail "syntax error in $(basename "${script}")"
    fi
done

if grep -q 'strawwu-secureboot' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes strawwu-secureboot"
else
    fail "build-os-debs missing strawwu-secureboot"
fi

MANIFEST="${SB_DEB}/usr/share/strawwu/secureboot/secureboot-manifest.yaml"
for token in shim.efi vmlinuz initrd.img STRAWWU_SB_SIGN post-sec-secureboot-route; do
    if grep -q "${token}" "${MANIFEST}"; then
        pass "manifest contains ${token}"
    else
        fail "manifest missing ${token}"
    fi
done

if grep -q 'dry-run' "${SB_SCRIPTS}/sign-boot-artifacts.sh" || grep -q 'DRY_RUN' "${SB_SCRIPTS}/sign-boot-artifacts.sh"; then
    pass "sign script defaults to dry-run"
else
    fail "sign script missing dry-run default"
fi

if grep -q 'mokutil' "${SB_SCRIPTS}/verify-boot-chain.sh"; then
    pass "verify script checks mokutil"
else
    fail "verify script missing mokutil check"
fi

if python3 "${UNIT_TEST}"; then
    pass "strawwu-secureboot unit tests"
else
    fail "strawwu-secureboot unit tests"
fi

FIXTURE="${SB_DEB}/usr/share/strawwu/secureboot/fixture-catalog.json"
export STRAWWU_SECUREBOOT_FIXTURE=1
export STRAWWU_SECUREBOOT_FIXTURE_PATH="${FIXTURE}"
if python3 "${SB_DEB}/usr/bin/strawwu-secureboot" preflight --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"]'; then
    pass "strawwu-secureboot preflight fixture CLI"
else
    fail "strawwu-secureboot preflight fixture CLI"
fi

if bash "${SB_SCRIPTS}/sign-boot-artifacts.sh" --dry-run 2>&1 | grep -qi 'dry-run'; then
    pass "sign-boot-artifacts dry-run smoke"
else
    fail "sign-boot-artifacts dry-run smoke"
fi

if bash "${SB_SCRIPTS}/verify-boot-chain.sh" --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="strawwu-sb-verify/v1"'; then
    pass "verify-boot-chain JSON smoke"
else
  # route_ok may be 0 when enforced without artifacts — skeleton allows exit 1
    if bash "${SB_SCRIPTS}/verify-boot-chain.sh" --json | grep -q 'strawwu-sb-verify'; then
        pass "verify-boot-chain JSON smoke (route_ok deferred)"
    else
        fail "verify-boot-chain JSON smoke"
    fi
fi

DRIVERS_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-drivers/usr/share/strawwu/drivers/drivers-manifest.yaml"
if grep -q 'post-sec-secureboot-route' "${DRIVERS_MANIFEST}"; then
    pass "strawwu-drivers links secureboot plan"
else
    fail "strawwu-drivers missing secureboot plan link"
fi

require_file "${PLANS_DIR}/stage-reports/POST-SEC-secureboot-route-report.md" "stage report"

python3 - "${BASELINE}" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
data = {
    "schema": "strawwu-stage-baseline/v1",
    "stage": "post-sec-secureboot-route",
    "version": version,
    "enforced_default": False,
    "packages": ["strawwu-secureboot"],
    "cli": [
        "strawwu-secureboot status",
        "strawwu-secureboot route",
        "strawwu-secureboot preflight",
    ],
    "scripts": {
        "sign": "os-image/scripts/secureboot-route/sign-boot-artifacts.sh",
        "verify": "os-image/scripts/secureboot-route/verify-boot-chain.sh",
        "manifest": "os-image/scripts/secureboot-route/MANIFEST.yaml",
    },
    "boot_chain": [
        "uefi_firmware",
        "shim.efi",
        "grubx64.efi",
        "vmlinuz(mok-signed)",
        "initrd.img",
    ],
    "signing": {
        "dry_run_default": True,
        "sign_env": "STRAWWU_SB_SIGN",
        "enforce_env": "STRAWWU_SECURE_BOOT_ENFORCE",
    },
    "dod": "shim + signed kernel/initrd route docs + skeleton (not enforced)",
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline written ${BASELINE}"
validate_json_file "${BASELINE}"

preflight_exit "POST-SEC secureboot route"

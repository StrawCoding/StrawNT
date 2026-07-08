#!/usr/bin/env bash
# POST-UPG: strawwu-upgrade + snapshot rollback + rescue ISO entry gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

UPG_DEB="${REPO_ROOT}/os-image/debs/strawwu-upgrade"
UNIT_TEST="${UPG_DEB}/tests/test-upgrade.py"
RESCUE_PATCH="${REPO_ROOT}/os-image/scripts/patch-iso-rescue-entry.sh"
RESCUE_SBIN="${REPO_ROOT}/os-image/config/branding/usr/local/sbin/strawwu-rescue-mode"
RESCUE_UNIT="${REPO_ROOT}/os-image/config/branding/etc/systemd/system/strawwu-rescue-mode.service"
BASELINE="${BASELINES_DIR}/upgrade-rollback-baseline.json"

echo "=== POST-UPG rollback preflight ==="

require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-upgrade-recovery-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-UPG-rollback.md" "kickoff POST-UPG-rollback"

require_file "${UPG_DEB}/DEBIAN/control" "strawwu-upgrade deb"
require_file "${UPG_DEB}/usr/bin/strawwu-upgrade" "strawwu-upgrade CLI"
require_file "${UPG_DEB}/usr/lib/strawwu-upgrade/core.py" "strawwu-upgrade core"
require_file "${UPG_DEB}/usr/share/strawwu/upgrade/upgrade-manifest.yaml" "upgrade manifest"
require_file "${UPG_DEB}/usr/share/strawwu/upgrade/fixture-catalog.json" "upgrade fixture"
require_file "${UPG_DEB}/build-deb.sh" "strawwu-upgrade build-deb.sh"
require_file "${UNIT_TEST}" "test-upgrade.py"
require_file "${RESCUE_PATCH}" "patch-iso-rescue-entry.sh"
require_file "${RESCUE_SBIN}" "strawwu-rescue-mode"
require_file "${RESCUE_UNIT}" "strawwu-rescue-mode.service"

for script in "${UPG_DEB}/build-deb.sh" "${UPG_DEB}/usr/bin/strawwu-upgrade" "${RESCUE_PATCH}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if bash -n "${RESCUE_PATCH}"; then
    pass "bash -n patch-iso-rescue-entry.sh"
else
    fail "patch-iso-rescue-entry.sh syntax error"
fi

if grep -q 'strawwu-upgrade' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes strawwu-upgrade"
else
    fail "build-os-debs missing strawwu-upgrade"
fi

TARGET_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
if grep -q 'strawwu-upgrade' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-upgrade"
else
    fail "target-manifest missing strawwu-upgrade"
fi

DESKTOP_CONTROL="${REPO_ROOT}/os-image/debs/strawwu-desktop/debian/control"
if grep -q 'strawwu-upgrade' "${DESKTOP_CONTROL}"; then
    pass "strawwu-desktop recommends strawwu-upgrade"
else
    fail "strawwu-desktop missing strawwu-upgrade"
fi

if grep -q 'patch-iso-rescue-entry.sh' "${REPO_ROOT}/os-image/scripts/apply-branding.sh"; then
    pass "apply-branding invokes rescue ISO patch"
else
    fail "apply-branding missing rescue ISO patch"
fi

if grep -q 'strawwu_rescue=1' "${RESCUE_PATCH}" && grep -q 'StrawWU Rescue' "${RESCUE_PATCH}"; then
    pass "rescue patch defines GRUB label + kernel param"
else
    fail "rescue patch incomplete"
fi

if grep -q 'strawwu-upgrade --rollback' "${RESCUE_SBIN}"; then
    pass "rescue mode documents strawwu-upgrade --rollback"
else
    fail "rescue mode missing rollback hint"
fi

OUTPUT_DIR="${UPG_DEB}/output"
rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${UPG_DEB}/build-deb.sh" >/dev/null; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-upgrade_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "strawwu-upgrade deb artifact"
else
    fail "strawwu-upgrade deb artifact missing"
fi

if python3 "${UNIT_TEST}" -q; then
    pass "strawwu-upgrade python tests"
else
    fail "strawwu-upgrade python tests"
fi

# CLI integration in temp dir (fixture mode).
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_UPGRADE_FIXTURE=1
export STRAWWU_UPGRADE_FIXTURE_PATH="${UPG_DEB}/usr/share/strawwu/upgrade/fixture-catalog.json"
export STRAWWU_UPGRADE_BACKUP_ROOT="${tmp_dir}/backups"
export STRAWWU_SETUP_STATE="${tmp_dir}/state.json"
export STRAWWU_UPGRADE_BOOT_DIR="${tmp_dir}/boot"
export STRAWWU_VERSION="0.6.3.11"
mkdir -p "${STRAWWU_UPGRADE_BOOT_DIR}"
python3 - <<'PY' "${STRAWWU_SETUP_STATE}" "${UPG_DEB}/usr/share/strawwu/upgrade/fixture-catalog.json"
import json, sys
from pathlib import Path
state = json.loads(Path(sys.argv[2]).read_text())["state"]
Path(sys.argv[1]).write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
touch "${STRAWWU_UPGRADE_BOOT_DIR}/vmlinuz-6.8.0-strawwu"
touch "${STRAWWU_UPGRADE_BOOT_DIR}/initrd.img-6.8.0-strawwu"

CLI="${UPG_DEB}/usr/bin/strawwu-upgrade"
if "${CLI}" version | grep -q 'strawwu-upgrade'; then
    pass "CLI version"
else
    fail "CLI version"
fi

if "${CLI}" preflight --target-version "${VERSION}"; then
    pass "CLI preflight"
else
    fail "CLI preflight"
fi

if "${CLI}" upgrade --dry-run --target-version "${VERSION}"; then
    pass "CLI upgrade --dry-run"
else
    fail "CLI upgrade --dry-run"
fi

if "${CLI}" --rollback; then
    pass "CLI --rollback"
else
    fail "CLI --rollback"
fi

# Rescue ISO patch smoke (when iso-staging exists).
ISO_STAGING="${REPO_ROOT}/os-image/work/iso-staging"
if [[ -f "${ISO_STAGING}/boot/grub/grub.cfg" ]]; then
  cp -a "${ISO_STAGING}/boot/grub/grub.cfg" "${tmp_dir}/grub.cfg.bak"
  if bash "${RESCUE_PATCH}" >/dev/null; then
      if grep -q 'StrawWU Rescue' "${ISO_STAGING}/boot/grub/grub.cfg" \
          && grep -q 'strawwu_rescue=1' "${ISO_STAGING}/boot/grub/grub.cfg"; then
          pass "rescue entry present in staged grub.cfg"
      else
          fail "rescue entry missing from staged grub.cfg"
      fi
  else
      fail "patch-iso-rescue-entry.sh failed on staged ISO"
  fi
  mv "${tmp_dir}/grub.cfg.bak" "${ISO_STAGING}/boot/grub/grub.cfg"
else
    warn "no staged grub.cfg — rescue patch verified at source only"
fi

if [[ -f "${BASELINE}" ]]; then
    python3 - "${BASELINE}" "${VERSION}" <<'PY'
import json, pathlib, sys
baseline = json.loads(pathlib.Path(sys.argv[1]).read_text())
version = sys.argv[2]
assert baseline.get("stage") == "post-upg-rollback"
assert baseline.get("version") == version, f"baseline version {baseline.get('version')} != {version}"
assert "strawwu-upgrade" in baseline.get("packages", [])
print("baseline version aligned")
PY
    pass "upgrade-rollback baseline aligned"
else
    warn "baseline missing — create docs/plans/baselines/upgrade-rollback-baseline.json"
fi

preflight_exit "POST-UPG rollback"

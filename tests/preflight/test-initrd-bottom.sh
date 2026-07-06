#!/usr/bin/env bash
# W8-S3: strawwu-live-bottom — forked casper-bottom hooks static checks + splice integration.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

LIVE_BOTTOM="${REPO_ROOT}/os-image/initrd/strawwu-live-bottom"
HOOKS="${LIVE_BOTTOM}/scripts"
ORDER="${HOOKS}/ORDER"
MANIFEST="${LIVE_BOTTOM}/MANIFEST.yaml"
BASELINE="${BASELINES_DIR}/initrd-bottom-baseline.json"
SPLICE="${REPO_ROOT}/os-image/scripts/initrd-splice.py"
CORE="${REPO_ROOT}/os-image/initrd/strawwu-live-init/scripts/strawwu-live-init"
STAGING_INITRD="${REPO_ROOT}/os-image/work/iso-staging/casper/initrd"
EXPECTED_HOOKS=34

echo "=== W8-S3 initrd bottom (strawwu-live-bottom) preflight ==="

require_plan "strawwu-initrd-plan.md"
require_file "${REPO_ROOT}/docs/plans/kickoff/W8-S3-initrd-bottom.md" "W8-S3 kickoff"
require_file "${ORDER}" "strawwu-live-bottom ORDER"
require_file "${MANIFEST}" "strawwu-live-bottom MANIFEST.yaml"
require_file "${BASELINE}" "initrd-bottom-baseline.json"
require_file "${SPLICE}" "initrd-splice.py"
require_file "${CORE}" "strawwu-live-init core"

legacy_overlay="${REPO_ROOT}/os-image/initrd/overlays/scripts/casper-bottom"
if [[ -d "${legacy_overlay}" ]]; then
	fail "legacy casper-bottom overlay still present — use strawwu-live-bottom/"
else
	pass "no duplicate casper-bottom overlay dir"
fi

hook_count=$(find "${HOOKS}" -maxdepth 1 -type f ! -name ORDER | wc -l)
if [[ "${hook_count}" -eq "${EXPECTED_HOOKS}" ]]; then
	pass "strawwu-live-bottom has ${EXPECTED_HOOKS} hook scripts"
else
	fail "expected ${EXPECTED_HOOKS} hooks, found ${hook_count}"
fi

if grep -q 'strawwu-live-bottom ORDER' "${ORDER}"; then
	pass "ORDER identifies strawwu-live-bottom"
else
	fail "ORDER missing strawwu-live-bottom header"
fi

if grep -q '/scripts/strawwu-live-bottom/' "${ORDER}" \
	&& ! grep -q '/scripts/casper-bottom/' "${ORDER}"; then
	pass "ORDER paths use strawwu-live-bottom"
else
	fail "ORDER still references casper-bottom paths"
fi

if [[ -f "${HOOKS}/25disable_cdrom.mount" ]] \
	&& grep -q 'live-shutdown' "${HOOKS}/25disable_cdrom.mount"; then
	pass "live-shutdown hook (25disable_cdrom.mount) present"
else
	fail "missing live-shutdown hook"
fi

for script in "${HOOKS}"/[0-9]*; do
	[[ -f "${script}" ]] || continue
	if [[ -x "${script}" ]]; then
		:
	else
		chmod +x "${script}"
	fi
done
pass "hook scripts executable"

if grep -q 'schema: strawwu-live-bottom-manifest/v1' "${MANIFEST}"; then
	pass "MANIFEST schema v1"
else
	fail "MANIFEST missing schema v1"
fi

if grep -q 'inject_strawwu_live_bottom' "${SPLICE}" \
	&& grep -q 'DEFAULT_LIVE_BOTTOM_ROOT' "${SPLICE}"; then
	pass "initrd-splice.py integrates strawwu-live-bottom"
else
	fail "initrd-splice.py missing inject_strawwu_live_bottom"
fi

if grep -q 'run_scripts /scripts/strawwu-live-bottom' "${CORE}"; then
	pass "strawwu-live-init runs strawwu-live-bottom"
else
	fail "strawwu-live-init still uses casper-bottom"
fi

if [[ -f "${STAGING_INITRD}" ]] && command -v unmkinitramfs >/dev/null 2>&1; then
	initrd_tmp=$(mktemp -d)
	if unmkinitramfs "${STAGING_INITRD}" "${initrd_tmp}" 2>/dev/null; then
		if [[ -f "${initrd_tmp}/main/scripts/strawwu-live-bottom/ORDER" ]]; then
			if grep -q 'strawwu-live-bottom' "${initrd_tmp}/main/scripts/strawwu-live-bottom/ORDER"; then
				pass "staged initrd contains strawwu-live-bottom ORDER"
			else
				fail "staged strawwu-live-bottom ORDER missing marker — rebuild initrd"
			fi
		else
			fail "staged initrd missing scripts/strawwu-live-bottom — run repack-iso"
		fi
		staged_hooks=$(find "${initrd_tmp}/main/scripts/strawwu-live-bottom" -maxdepth 1 -type f ! -name ORDER | wc -l)
		if [[ "${staged_hooks}" -eq "${EXPECTED_HOOKS}" ]]; then
			pass "staged initrd has ${EXPECTED_HOOKS} strawwu-live-bottom hooks"
		else
			fail "staged initrd hook count ${staged_hooks} != ${EXPECTED_HOOKS}"
		fi
		if [[ -f "${initrd_tmp}/main/scripts/casper-bottom/ORDER" ]] \
			&& grep -q '/scripts/strawwu-live-bottom/' "${initrd_tmp}/main/scripts/casper-bottom/ORDER"; then
			pass "staged casper-bottom compat ORDER delegates to strawwu-live-bottom"
		else
			fail "staged casper-bottom compat shim missing or wrong"
		fi
		if grep -q 'run_scripts /scripts/strawwu-live-bottom' "${initrd_tmp}/main/scripts/strawwu-live-init"; then
			pass "staged initrd core runs strawwu-live-bottom"
		else
			fail "staged initrd core still references casper-bottom runner"
		fi
	else
		warn "unmkinitramfs failed on staged initrd — skipping injected bottom checks"
	fi
	rm -rf "${initrd_tmp}"
else
	warn "no staged casper initrd — bottom verified at source only"
fi

echo "=== W8-S3 initrd bottom done ==="
exit "${PREFLIGHT_FAIL}"

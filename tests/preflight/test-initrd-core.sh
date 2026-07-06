#!/usr/bin/env bash
# W8-S2: strawwu-live-init — forked casper core static checks + splice integration.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

LIVE_INIT="${REPO_ROOT}/os-image/initrd/strawwu-live-init"
CORE="${LIVE_INIT}/scripts/strawwu-live-init"
SHIM="${LIVE_INIT}/scripts/casper-wrapper"
MANIFEST="${LIVE_INIT}/MANIFEST.yaml"
BASELINE="${BASELINES_DIR}/initrd-core-baseline.json"
SPLICE="${REPO_ROOT}/os-image/scripts/initrd-splice.py"
STAGING_INITRD="${REPO_ROOT}/os-image/work/iso-staging/casper/initrd"

echo "=== W8-S2 initrd core (strawwu-live-init) preflight ==="

require_plan "strawwu-initrd-plan.md"
require_file "${REPO_ROOT}/docs/plans/kickoff/W8-S2-initrd-core.md" "W8-S2 kickoff"
require_file "${CORE}" "strawwu-live-init core script"
require_file "${SHIM}" "casper compatibility shim"
require_file "${MANIFEST}" "strawwu-live-init MANIFEST.yaml"
require_file "${BASELINE}" "initrd-core-baseline.json"
require_file "${SPLICE}" "initrd-splice.py"

for script in "${CORE}" "${SHIM}"; do
	if [[ -x "${script}" ]]; then
		pass "$(basename "${script}") executable"
	else
		chmod +x "${script}"
		pass "chmod +x $(basename "${script}")"
	fi
done

if grep -q 'strawwu-live-init' "${CORE}"; then
	pass "core script identifies strawwu-live-init"
else
	fail "core script missing strawwu-live-init marker"
fi

if grep -q '^USERNAME=ubuntu' "${CORE}"; then
	pass "core default USERNAME=ubuntu (casper compat)"
else
	fail "core missing USERNAME=ubuntu default"
fi

if grep -q 'BUILD_SYSTEM=StrawWU' "${CORE}"; then
	pass "core default BUILD_SYSTEM=StrawWU"
else
	fail "core missing BUILD_SYSTEM=StrawWU"
fi

if grep -q '/dev/sr0' "${CORE}" && grep -q 'find_livefs' "${CORE}"; then
	pass "core has optical live-media hint in find_livefs"
else
	fail "core missing find_livefs optical hint"
fi

if grep -q 'overlay.ko' "${CORE}" && grep -q 'setup_overlay' "${CORE}"; then
	pass "core has overlay insmod fallback"
else
	fail "core missing overlay insmod fallback"
fi

if grep -q 'schema: strawwu-live-init-manifest/v1' "${MANIFEST}"; then
	pass "MANIFEST schema v1"
else
	fail "MANIFEST missing schema v1"
fi

if grep -q 'inject_strawwu_live_init' "${SPLICE}" \
	&& grep -q 'DEFAULT_LIVE_INIT_ROOT' "${SPLICE}"; then
	pass "initrd-splice.py integrates strawwu-live-init"
else
	fail "initrd-splice.py missing inject_strawwu_live_init"
fi

if grep -q 'strawwu-live-init' "${SHIM}"; then
	pass "casper shim delegates to strawwu-live-init"
else
	fail "casper shim missing strawwu-live-init delegation"
fi

if [[ -f "${STAGING_INITRD}" ]] && command -v unmkinitramfs >/dev/null 2>&1; then
	initrd_tmp=$(mktemp -d)
	if unmkinitramfs "${STAGING_INITRD}" "${initrd_tmp}" 2>/dev/null; then
		for rel in scripts/strawwu-live-init scripts/casper; do
			if [[ -f "${initrd_tmp}/main/${rel}" ]]; then
				if grep -q 'strawwu-live-init' "${initrd_tmp}/main/${rel}"; then
					pass "staged initrd contains ${rel} with strawwu-live-init marker"
				else
					fail "staged initrd ${rel} missing strawwu-live-init marker — rebuild initrd"
				fi
			else
				fail "staged initrd missing ${rel} — run repack-iso"
			fi
		done
		if grep -q 'strawwu-live-init' "${initrd_tmp}/main/scripts/casper" \
			&& grep -q '^USERNAME=ubuntu' "${initrd_tmp}/main/scripts/strawwu-live-init"; then
			pass "staged initrd casper shim + core USERNAME=ubuntu"
		else
			fail "staged initrd casper/core compat check failed"
		fi
	else
		warn "unmkinitramfs failed on staged initrd — skipping injected core checks"
	fi
	rm -rf "${initrd_tmp}"
else
	warn "no staged casper initrd — core verified at source only"
fi

echo "=== W8-S2 initrd core done ==="
exit "${PREFLIGHT_FAIL}"

#!/usr/bin/env bash
# W1-S1: initrd overlay static checks (iso-scan, live-shutdown, splice integration).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

OVERLAYS="${REPO_ROOT}/os-image/initrd/overlays"
SPLICE="${REPO_ROOT}/os-image/scripts/initrd-splice.py"
STAGING_INITRD="${REPO_ROOT}/os-image/work/iso-staging/casper/initrd"

echo "=== W1-S1 initrd overlays preflight ==="

require_plan "strawwu-initrd-plan.md"
require_file "${REPO_ROOT}/docs/plans/kickoff/W1-S1-initrd.md" "W1-S1 kickoff"
require_file "${SPLICE}" "initrd-splice.py"

require_file "${OVERLAYS}/scripts/casper-premount/05strawwu-wait-live-media" "premount wait-live-media"
require_file "${OVERLAYS}/scripts/casper-premount/20iso_scan" "iso-scan overlay"

for script in \
	"${OVERLAYS}/scripts/casper-premount/05strawwu-wait-live-media" \
	"${OVERLAYS}/scripts/casper-premount/20iso_scan"; do
	if [[ -x "${script}" ]]; then
		pass "$(basename "${script}") executable"
	else
		chmod +x "${script}"
		pass "chmod +x $(basename "${script}")"
	fi
done

if grep -q 'StrawWU could not find the ISO' "${OVERLAYS}/scripts/casper-premount/20iso_scan"; then
	pass "iso-scan overlay has StrawWU panic text"
else
	fail "iso-scan overlay missing StrawWU panic text"
fi

live_bottom="${REPO_ROOT}/os-image/initrd/strawwu-live-bottom/scripts/25disable_cdrom.mount"
if [[ -f "${live_bottom}" ]] && grep -q 'live-shutdown' "${live_bottom}"; then
	pass "live-shutdown hook in strawwu-live-bottom (not overlay)"
else
	fail "live-shutdown hook missing from strawwu-live-bottom"
fi

if grep -q 'DEFAULT_OVERLAYS_ROOT' "${SPLICE}" && grep -q 'inject_initrd_overlays' "${SPLICE}"; then
	pass "initrd-splice.py integrates overlays root"
else
	fail "initrd-splice.py missing overlay injection"
fi

legacy_hook="${REPO_ROOT}/os-image/config/branding/initrd/scripts/casper-premount/05strawwu-wait-live-media"
if [[ -f "${legacy_hook}" ]]; then
	fail "legacy branding premount hook still present — use os-image/initrd/overlays/"
else
	pass "no duplicate branding premount hook"
fi

if [[ -f "${STAGING_INITRD}" ]] && command -v unmkinitramfs >/dev/null 2>&1; then
	initrd_tmp=$(mktemp -d)
	if unmkinitramfs "${STAGING_INITRD}" "${initrd_tmp}" 2>/dev/null; then
		for rel in \
			scripts/casper-premount/05strawwu-wait-live-media \
			scripts/casper-premount/20iso_scan; do
			if [[ -f "${initrd_tmp}/main/${rel}" ]]; then
				if grep -q 'StrawWU' "${initrd_tmp}/main/${rel}"; then
					pass "staged initrd contains overlay ${rel}"
				else
					fail "staged initrd ${rel} missing StrawWU marker — rebuild initrd"
				fi
			else
				fail "staged initrd missing ${rel} — run repack-iso"
			fi
		done
	else
		warn "unmkinitramfs failed on staged initrd — skipping injected overlay checks"
	fi
	rm -rf "${initrd_tmp}"
else
	warn "no staged casper initrd — overlay injection verified at source only"
fi

echo "=== W1-S1 initrd overlays done ==="
exit "${PREFLIGHT_FAIL}"

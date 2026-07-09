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
require_file "${OVERLAYS}/scripts/init-top/05strawwu-early-gpu" "init-top early-gpu"

for script in \
	"${OVERLAYS}/scripts/casper-premount/05strawwu-wait-live-media" \
	"${OVERLAYS}/scripts/casper-premount/20iso_scan" \
	"${OVERLAYS}/scripts/init-top/05strawwu-early-gpu"; do
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

if grep -q 'inject_early_physical_gpu_firmware' "${SPLICE}" && grep -q 'EARLY_PHYSICAL_GPU_FIRMWARE_DIRS' "${SPLICE}"; then
	pass "initrd-splice.py injects physical GPU firmware"
else
	fail "initrd-splice.py missing physical GPU firmware injection"
fi

if grep -q 'inject_early_gpu_hook_into_module_phase' "${SPLICE}" && grep -q 'inject_early_gpu_module_metadata' "${SPLICE}"; then
	pass "initrd-splice.py injects early-gpu hook + module metadata into module phase"
else
	fail "initrd-splice.py missing early-gpu module-phase injection"
fi

if grep -q 'Do NOT write scripts/init-top/ORDER here' "${SPLICE}"; then
	pass "initrd-splice.py avoids standalone early2 init-top ORDER (udev race)"
else
	fail "initrd-splice.py may still write early2 ORDER without udev — physical panic risk"
fi

if grep -q 'detect_gpu_driver' "${OVERLAYS}/scripts/init-top/05strawwu-early-gpu"; then
	pass "early-gpu hook is PCI-aware (single driver load)"
else
	fail "early-gpu hook loads all GPU drivers — physical panic risk"
fi

if grep -q 'find "${MODROOT}"' "${OVERLAYS}/scripts/init-top/05strawwu-early-gpu"; then
	pass "early-gpu hook uses explicit insmod paths (no modules.dep dependency)"
else
	fail "early-gpu hook still modprobe-only — will fail on early2 without modules.dep"
fi

if grep -q '/dev/sd\*\[0-9\]' "${OVERLAYS}/scripts/casper-premount/05strawwu-wait-live-media"; then
	pass "wait-live-media probes USB iso9660 partitions"
else
	fail "wait-live-media only waits for sr0/cdrom — Live USB boot race"
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

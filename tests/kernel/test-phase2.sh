#!/usr/bin/env bash
# test-phase2.sh — Phase 2 acceptance: custom kernel deb + swap marker + version string.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${REPO_ROOT}/os-image/work"
KERNEL_OUT="${REPO_ROOT}/kernel/output"
MOK_CRT="${REPO_ROOT}/os-image/keys/secureboot/StrawWU-MOK.crt"

fail() { echo "test-phase2: FAIL — $*" >&2; exit 1; }
pass() { echo "test-phase2: PASS — $*"; }

[[ -f "${KERNEL_OUT}/.build-ok" ]] || fail "kernel build marker missing"
deb="$(find "${KERNEL_OUT}" -maxdepth 1 -name 'linux-image-strawwu_*.deb' | head -1)"
[[ -n "${deb}" ]] || fail "linux-image-strawwu deb missing"

[[ -f "${WORK_DIR}/.swap-kernel-ok" ]] || fail "swap-kernel marker missing"
grep -q strawwu "${WORK_DIR}/.swap-kernel-ok" || fail "swap marker does not reference strawwu kernel"
grep -q 'mok_signed:mok-signed' "${WORK_DIR}/.swap-kernel-ok" \
    || fail "swap marker does not confirm MOK-signed custom kernel"

[[ -f "${KERNEL_OUT}/.kernel-signing" ]] || fail "kernel signing manifest missing"
grep -q '^module_sig=enabled$' "${KERNEL_OUT}/.kernel-signing" \
    || fail "kernel signing manifest does not enable module signatures"
grep -q '^kernel_mok_signed=true$' "${KERNEL_OUT}/.kernel-signing" \
    || fail "kernel signing manifest does not confirm vmlinuz signature"

# rootfs should have strawwu kernel image installed
vmlinuz="$(find "${WORK_DIR}/rootfs/boot" -name 'vmlinuz-*strawwu*' 2>/dev/null | head -1)"
[[ -n "${vmlinuz}" ]] || fail "no vmlinuz-*strawwu* in rootfs /boot"

mod_dir="$(find "${WORK_DIR}/rootfs/lib/modules" -maxdepth 1 -name '*strawwu*' 2>/dev/null | head -1)"
[[ -n "${mod_dir}" ]] || fail "no *strawwu* modules dir in rootfs"
[[ -f "${mod_dir}/kernel/drivers/misc/strawwu_ipc/strawwu_ipc.ko" \
    || -f "${mod_dir}/extra/strawwu_ipc.ko" ]] || fail "strawwu_ipc.ko not in modules tree"

config="${WORK_DIR}/rootfs/boot/config-$(basename "${mod_dir}")"
[[ -f "${config}" ]] || fail "custom kernel config missing"
grep -q '^CONFIG_MODULE_SIG=y$' "${config}" || fail "CONFIG_MODULE_SIG is not enabled"
grep -q '^# CONFIG_MODULE_SIG_ALL is not set$' "${config}" \
    || fail "CONFIG_MODULE_SIG_ALL must be disabled for persistent explicit MOK signing"

command -v sbverify >/dev/null 2>&1 || fail "sbverify unavailable"
command -v modinfo >/dev/null 2>&1 || fail "modinfo unavailable"
[[ -f "${MOK_CRT}" ]] || fail "MOK certificate missing"
sbverify --cert "${MOK_CRT}" "${vmlinuz}" >/dev/null 2>&1 \
    || fail "rootfs custom vmlinuz is not signed by StrawWU MOK"

unsigned=0
module_count=0
while IFS= read -r -d '' module; do
    module_count=$((module_count + 1))
    signer="$(modinfo -F signer "${module}" 2>/dev/null || true)"
    if [[ "${signer}" != *StrawWU* ]]; then
        echo "test-phase2: unsigned or wrong signer: ${module}" >&2
        unsigned=$((unsigned + 1))
    fi
done < <(find "${mod_dir}" -type f \
    \( -name '*.ko' -o -name '*.ko.zst' -o -name '*.ko.xz' -o -name '*.ko.gz' \) -print0)
[[ "${module_count}" -gt 0 ]] || fail "no custom kernel modules found"
[[ "${unsigned}" -eq 0 ]] || fail "${unsigned}/${module_count} custom kernel modules are not MOK-signed"

pass "deb=${deb} vmlinuz=${vmlinuz} modules=${module_count} all MOK-signed"

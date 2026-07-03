#!/usr/bin/env bash
# test-phase2.sh — Phase 2 acceptance: custom kernel deb + swap marker + version string.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${REPO_ROOT}/os-image/work"
KERNEL_OUT="${REPO_ROOT}/kernel/output"

fail() { echo "test-phase2: FAIL — $*" >&2; exit 1; }
pass() { echo "test-phase2: PASS — $*"; }

[[ -f "${KERNEL_OUT}/.build-ok" ]] || fail "kernel build marker missing"
deb="$(find "${KERNEL_OUT}" -maxdepth 1 -name 'linux-image-strawwu_*.deb' | head -1)"
[[ -n "${deb}" ]] || fail "linux-image-strawwu deb missing"

[[ -f "${WORK_DIR}/.swap-kernel-ok" ]] || fail "swap-kernel marker missing"
grep -q strawwu "${WORK_DIR}/.swap-kernel-ok" || fail "swap marker does not reference strawwu kernel"

# rootfs should have strawwu kernel image installed
vmlinuz="$(find "${WORK_DIR}/rootfs/boot" -name 'vmlinuz-*strawwu*' 2>/dev/null | head -1)"
[[ -n "${vmlinuz}" ]] || fail "no vmlinuz-*strawwu* in rootfs /boot"

mod_dir="$(find "${WORK_DIR}/rootfs/lib/modules" -maxdepth 1 -name '*strawwu*' 2>/dev/null | head -1)"
[[ -n "${mod_dir}" ]] || fail "no *strawwu* modules dir in rootfs"
[[ -f "${mod_dir}/kernel/drivers/misc/strawwu_ipc/strawwu_ipc.ko" \
    || -f "${mod_dir}/extra/strawwu_ipc.ko" ]] || fail "strawwu_ipc.ko not in modules tree"

pass "deb=${deb} vmlinuz=${vmlinuz}"

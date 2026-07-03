#!/usr/bin/env bash
# Run dev-vm test command inside VM after sync.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_env

ensure_qemu_running

cmd="${STRAWWU_DEV_VM_TEST_CMD:-echo STRAWWU_DEV_VM_OK}"
log "running test: ${cmd}"
if vm_ssh "bash -lc $(printf '%q' "${cmd}")"; then
    echo "PASS: dev-vm test"
    exit 0
fi
echo "FAIL: dev-vm test" >&2
exit 1

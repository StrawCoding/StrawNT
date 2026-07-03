#!/usr/bin/env bash
# Save VM snapshot (qemu backend only).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_env

[[ "${STRAWWU_DEV_VM_BACKEND}" == qemu ]] || die "snapshot only for qemu backend"

name="${STRAWWU_DEV_VM_QEMU_NAME:-strawwu-dev}"
snap="${STRAWWU_DEV_VM_QEMU_SNAPSHOT:-dev-clean}"
disk="${STRAWWU_DEV_VM_QEMU_DISK:?}"

if ! pgrep -af "qemu-system-x86_64.*${name}" >/dev/null; then
    die "QEMU ${name} not running"
fi

log "saving snapshot ${snap} on ${disk}"
qemu-img snapshot -c "${snap}" "${disk}"
echo "PASS: snapshot ${snap} saved"

#!/usr/bin/env bash
# Rollback VM to clean snapshot (qemu) or no-op hint (ssh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_env

case "${STRAWWU_DEV_VM_BACKEND}" in
    qemu)
        name="${STRAWWU_DEV_VM_QEMU_NAME:-strawwu-dev}"
        snap="${STRAWWU_DEV_VM_QEMU_SNAPSHOT:-dev-clean}"
        disk="${STRAWWU_DEV_VM_QEMU_DISK:?}"
        if pgrep -af "qemu-system-x86_64.*${name}" >/dev/null; then
            log "stopping QEMU ${name}"
            pkill -f "qemu-system-x86_64.*${name}" || true
            sleep 2
        fi
        log "reverting ${disk} → snapshot ${snap}"
        qemu-img snapshot -a "${snap}" "${disk}"
        echo "PASS: rolled back to ${snap}"
        ;;
    ssh)
        die "ssh backend has no snapshot — reinstall VM or use qemu backend for snapshot workflow"
        ;;
    *)
        die "unknown backend"
        ;;
esac

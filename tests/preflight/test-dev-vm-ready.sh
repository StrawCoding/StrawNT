#!/usr/bin/env bash
# Preflight: dev-vm backend reachable before running in-VM tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${STRAWWU_DEV_VM_ENV:-${SCRIPT_DIR}/../dev-vm/vm.env}"
FAIL=0

echo "=== StrawWU dev-vm preflight ==="

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "FAIL: missing ${ENV_FILE} (copy vm.env.example)" >&2
    exit 1
fi
echo "PASS: vm.env exists"

# shellcheck disable=SC1090
source "${ENV_FILE}"
backend="${STRAWWU_DEV_VM_BACKEND:-qemu}"

case "${backend}" in
    qemu)
        disk="${STRAWWU_DEV_VM_QEMU_DISK:-}"
        if [[ -n "${disk}" && -f "${disk}" ]]; then
            echo "PASS: QEMU disk ${disk}"
        else
            echo "FAIL: QEMU disk missing (${disk:-unset})" >&2
            FAIL=1
        fi
        port="${STRAWWU_DEV_VM_QEMU_SSH_PORT:-2222}"
        if ss -ltn 2>/dev/null | grep -q ":${port} "; then
            echo "PASS: SSH forwarded on :${port}"
        else
            echo "WARN: no listener on :${port} — run make dev-vm-start or sync will start QEMU"
        fi
        ;;
    ssh)
        host="${STRAWWU_DEV_VM_SSH_HOST:-}"
        [[ -n "${host}" ]] && echo "PASS: SSH host ${host}" || { echo "FAIL: SSH host unset" >&2; FAIL=1; }
        ;;
    *)
        echo "FAIL: unknown backend ${backend}" >&2
        FAIL=1
        ;;
esac

echo "=== dev-vm preflight done ==="
exit "${FAIL}"

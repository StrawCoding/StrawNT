#!/usr/bin/env bash
set -euo pipefail

DEV_VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DEV_VM_DIR}/../.." && pwd)"
ENV_FILE="${STRAWWU_DEV_VM_ENV:-${DEV_VM_DIR}/vm.env}"

log() { echo "==> [dev-vm] $*" >&2; }
die() { echo "ERROR [dev-vm]: $*" >&2; exit 1; }

load_env() {
    [[ -f "${ENV_FILE}" ]] || die "missing ${ENV_FILE} — copy vm.env.example → vm.env"
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    STRAWWU_DEV_VM_BACKEND="${STRAWWU_DEV_VM_BACKEND:-qemu}"
}

vm_ssh() {
    local host port user key_args=()
    case "${STRAWWU_DEV_VM_BACKEND}" in
        qemu)
            host=127.0.0.1
            port="${STRAWWU_DEV_VM_QEMU_SSH_PORT:-2222}"
            user="${STRAWWU_DEV_VM_SSH_USER:-ubuntu}"
            ;;
        ssh)
            host="${STRAWWU_DEV_VM_SSH_HOST:?}"
            port="${STRAWWU_DEV_VM_SSH_PORT:-22}"
            user="${STRAWWU_DEV_VM_SSH_USER:-ubuntu}"
            ;;
        *)
            die "unknown backend ${STRAWWU_DEV_VM_BACKEND}"
            ;;
    esac
    if [[ -n "${STRAWWU_DEV_VM_SSH_KEY:-}" ]]; then
        key_args=(-i "${STRAWWU_DEV_VM_SSH_KEY}")
    fi
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
        -p "${port}" "${key_args[@]}" "${user}@${host}" "$@"
}

ensure_qemu_running() {
    [[ "${STRAWWU_DEV_VM_BACKEND}" == qemu ]] || return 0
    local name="${STRAWWU_DEV_VM_QEMU_NAME:-strawwu-dev}"
    if pgrep -af "qemu-system-x86_64.*${name}" >/dev/null 2>&1; then
        log "QEMU ${name} already running"
        return 0
    fi
    local disk="${STRAWWU_DEV_VM_QEMU_DISK:?}"
    [[ -f "${disk}" ]] || die "QEMU disk missing: ${disk} (install base image first)"
    local mem="${STRAWWU_DEV_VM_QEMU_MEMORY:-4096}"
    local port="${STRAWWU_DEV_VM_QEMU_SSH_PORT:-2222}"
    log "starting QEMU ${name} (ssh :${port})"
    qemu-system-x86_64 \
        -name "${name}" \
        -m "${mem}" \
        -smp 2 \
        -drive "file=${disk},format=qcow2,if=virtio" \
        -netdev user,id=net0,hostfwd=tcp::${port}-:22 \
        -device virtio-net-pci,netdev=net0 \
        -display none \
        -daemonize
    sleep 8
    for _ in $(seq 1 30); do
        if vm_ssh true 2>/dev/null; then
            log "SSH ready"
            return 0
        fi
        sleep 2
    done
    die "QEMU started but SSH not reachable on port ${port}"
}

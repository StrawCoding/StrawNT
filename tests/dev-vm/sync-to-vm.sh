#!/usr/bin/env bash
# Rsync selected repo paths into running StrawWU VM (dev-vm mode — no ISO).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_env

ensure_qemu_running

paths="${STRAWWU_DEV_VM_SYNC_PATHS:-components/}"
read -r -a sync_paths <<< "${paths}"

host port user key_args=()
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
esac
if [[ -n "${STRAWWU_DEV_VM_SSH_KEY:-}" ]]; then
    key_args=(-e "ssh -i ${STRAWWU_DEV_VM_SSH_KEY} -p ${port}")
else
    key_args=(-e "ssh -p ${port}")
fi

remote_root="${STRAWWU_DEV_VM_REMOTE_ROOT:-/opt/strawwu-dev}"
vm_ssh "sudo mkdir -p ${remote_root}"

for rel in "${sync_paths[@]}"; do
    src="${REPO_ROOT}/${rel}"
    [[ -e "${src}" ]] || { log "skip missing ${rel}"; continue; }
    log "rsync ${rel} → ${user}@${host}:${remote_root}/"
    rsync -az --delete "${key_args[@]}" \
        "${src}" "${user}@${host}:${remote_root}/$(basename "${rel}")/"
done

services="${STRAWWU_DEV_VM_RESTART_SERVICES:-}"
if [[ -n "${services}" ]]; then
    read -r -a units <<< "${services}"
    for unit in "${units[@]}"; do
        log "restart ${unit}"
        vm_ssh "sudo systemctl restart ${unit}" || true
    done
fi

echo "PASS: dev-vm sync complete"

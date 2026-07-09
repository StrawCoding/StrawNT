#!/usr/bin/env bash
# sign-boot-artifacts.sh — StrawWU Secure Boot signing (MOK single track, dry-run default).
#
# StrawWU uses ONE Secure Boot track: shim + grub stay Canonical/Microsoft-signed
# and only the custom StrawWU kernel is signed with the StrawWU MOK. There is no
# self-owned UEFI DB key (that would require firmware-level enrollment end users
# cannot do). This script therefore MOK-signs the kernel and records the initrd
# hash; shim/grub are left untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BOOT_DIR="${STRAWWU_SB_BOOT_DIR:-/boot}"
KEY_DIR="${STRAWWU_SB_KEY_DIR:-${STRAWWU_MOK_DIR:-${REPO_ROOT}/os-image/keys/secureboot}}"
DRY_RUN=1
SIGN=0

usage() {
    cat <<'EOF'
Usage: sign-boot-artifacts.sh [--dry-run|--sign] [--boot-dir DIR] [--key-dir DIR]

MOK-signs the StrawWU kernel and records the initrd hash for the StrawWU Secure
Boot route (shim/grub remain Canonical-signed — single MOK track). Default:
dry-run. Set STRAWWU_SB_SIGN=1 or pass --sign to attempt real signing when the
StrawWU MOK and sbsign are available.
EOF
}

log() { echo "==> $*" >&2; }
warn() { echo "WARN: $*" >&2; }

have_tool() {
    command -v "$1" >/dev/null 2>&1
}

sign_pe() {
    local artifact="$1"
    local key="$2"
    local cert="$3"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] would sign PE ${artifact}"
        return 0
    fi
    if have_tool sbsign; then
        sbsign --key "${key}" --cert "${cert}" "${artifact}"
        log "signed ${artifact} (sbsign)"
    elif have_tool pesign; then
        pesign -n "${cert}" -i "${artifact}" -o "${artifact}.signed"
        mv "${artifact}.signed" "${artifact}"
        log "signed ${artifact} (pesign)"
    else
        warn "no sbsign/pesign — skip ${artifact}"
        return 1
    fi
}

sign_file_hash() {
    local artifact="$1"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] would record hash for ${artifact}"
        return 0
    fi
    if [[ -f "${artifact}" ]]; then
        sha256sum "${artifact}" | tee -a "${BOOT_DIR}/.strawwu-sb-hashes.txt"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; SIGN=0; shift ;;
        --sign) DRY_RUN=0; SIGN=1; shift ;;
        --boot-dir) BOOT_DIR="$2"; shift 2 ;;
        --key-dir) KEY_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ "${STRAWWU_SB_SIGN:-0}" == "1" ]]; then
    DRY_RUN=0
    SIGN=1
fi

log "StrawWU secureboot MOK sign boot_dir=${BOOT_DIR} dry-run=${DRY_RUN}"

# MOK single track: only the kernel is MOK-signed; shim/grub keep their upstream
# (Canonical/Microsoft) signatures. The initrd is not PE-signed (grub measures it
# via the signed kernel) — we only record its hash.
KERNELS=(
    "${BOOT_DIR}/vmlinuz"
)
INITRDS=(
    "${BOOT_DIR}/initrd.img"
)

MOK_KEY="${KEY_DIR}/StrawWU-MOK.key"
MOK_CERT="${KEY_DIR}/StrawWU-MOK.crt"

if [[ "${SIGN}" -eq 1 && ! -f "${MOK_KEY}" ]]; then
    warn "signing requested but MOK key missing: ${MOK_KEY} — falling back to dry-run"
    DRY_RUN=1
fi

for path in "${KERNELS[@]}"; do
    if [[ ! -f "${path}" ]]; then
        warn "kernel missing (ok for skeleton/CI): ${path}"
        continue
    fi
    sign_pe "${path}" "${MOK_KEY}" "${MOK_CERT}" || true
done

for path in "${INITRDS[@]}"; do
    if [[ ! -f "${path}" ]]; then
        warn "initrd missing (ok for skeleton/CI): ${path}"
        continue
    fi
    sign_file_hash "${path}"
done

log "done (enforced=${STRAWWU_SECURE_BOOT_ENFORCE:-0})"

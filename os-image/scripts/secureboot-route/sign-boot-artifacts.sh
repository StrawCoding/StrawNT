#!/usr/bin/env bash
# sign-boot-artifacts.sh — StrawWU Secure Boot signing skeleton (dry-run by default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BOOT_DIR="${STRAWWU_SB_BOOT_DIR:-/boot}"
KEY_DIR="${STRAWWU_SB_KEY_DIR:-${REPO_ROOT}/os-image/keys/secureboot}"
DRY_RUN=1
SIGN=0

usage() {
    cat <<'EOF'
Usage: sign-boot-artifacts.sh [--dry-run|--sign] [--boot-dir DIR] [--key-dir DIR]

Signs (or dry-runs) shim, grub, kernel, and initrd for the StrawWU SB route.
Default: dry-run. Set STRAWWU_SB_SIGN=1 or pass --sign to attempt real signing
when keys and sbsign/pesign are available.
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

log "StrawWU secureboot sign skeleton boot_dir=${BOOT_DIR} dry-run=${DRY_RUN}"

ARTIFACTS=(
    "${BOOT_DIR}/EFI/BOOT/shim.efi"
    "${BOOT_DIR}/EFI/BOOT/grubx64.efi"
    "${BOOT_DIR}/vmlinuz"
    "${BOOT_DIR}/initrd.img"
)

DB_KEY="${KEY_DIR}/StrawWU-SB-DB.key"
DB_CERT="${KEY_DIR}/StrawWU-SB-DB.crt"

if [[ "${SIGN}" -eq 1 && ! -f "${DB_KEY}" ]]; then
    warn "signing requested but key missing: ${DB_KEY} — falling back to dry-run"
    DRY_RUN=1
fi

for path in "${ARTIFACTS[@]}"; do
    if [[ ! -f "${path}" ]]; then
        warn "artifact missing (ok for skeleton): ${path}"
        continue
    fi
    case "${path}" in
        *.efi)
            sign_pe "${path}" "${DB_KEY}" "${DB_CERT}" || true
            ;;
        *)
            sign_file_hash "${path}"
            ;;
    esac
done

log "done (enforced=${STRAWWU_SECURE_BOOT_ENFORCE:-0})"

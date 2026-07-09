#!/usr/bin/env bash
# mok-sign.sh — Sign a PE/kernel image with the StrawWU MOK (idempotent).
# Usage: mok-sign.sh <file> [file...]
# No-op (exit 0) if the MOK key is absent so pipelines without keys still build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KEY_DIR="${STRAWWU_MOK_DIR:-${REPO_ROOT}/os-image/keys/secureboot}"
MOK_KEY="${KEY_DIR}/StrawWU-MOK.key"
MOK_CRT="${KEY_DIR}/StrawWU-MOK.crt"

log() { echo "==> mok-sign: $*" >&2; }
warn() { echo "WARN: mok-sign: $*" >&2; }

if [[ ! -f "${MOK_KEY}" || ! -f "${MOK_CRT}" ]]; then
    warn "MOK key missing (${MOK_KEY}) — skipping signing"
    exit 0
fi
command -v sbsign >/dev/null 2>&1 || { warn "sbsign not installed — skipping"; exit 0; }
command -v sbverify >/dev/null 2>&1 || true

already_signed_by_mok() {
    local f="$1"
    command -v sbverify >/dev/null 2>&1 || return 1
    sbverify --cert "${MOK_CRT}" "${f}" >/dev/null 2>&1
}

sign_one() {
    local f="$1"
    [[ -f "${f}" ]] || { warn "missing: ${f}"; return 0; }
    if already_signed_by_mok "${f}"; then
        log "already MOK-signed: ${f}"
        return 0
    fi
    local tmp="${f}.mok-signed"
    if sbsign --key "${MOK_KEY}" --cert "${MOK_CRT}" --output "${tmp}" "${f}" 2>/dev/null; then
        # Preserve ownership/permissions of the original.
        cat "${tmp}" > "${f}"
        rm -f "${tmp}"
        log "signed with MOK: ${f}"
    else
        rm -f "${tmp}"
        warn "sbsign failed for ${f} (already signed with another key?) — leaving as-is"
    fi
}

for f in "$@"; do
    sign_one "${f}"
done

#!/usr/bin/env bash
# mok-sign.sh — Sign a PE/kernel image with the StrawWU MOK (idempotent).
# Usage: mok-sign.sh <file> [file...]
# Set STRAWWU_REQUIRE_MOK=1 for release/custom-kernel builds that must be signed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KEY_DIR="${STRAWWU_MOK_DIR:-${REPO_ROOT}/os-image/keys/secureboot}"
MOK_KEY="${KEY_DIR}/StrawWU-MOK.key"
MOK_CRT="${KEY_DIR}/StrawWU-MOK.crt"
REQUIRE_MOK="${STRAWWU_REQUIRE_MOK:-0}"

log() { echo "==> mok-sign: $*" >&2; }
warn() { echo "WARN: mok-sign: $*" >&2; }

skip_or_fail() {
    if [[ "${REQUIRE_MOK}" == "1" ]]; then
        echo "ERROR: mok-sign: $*" >&2
        exit 1
    fi
    warn "$*"
    exit 0
}

if [[ ! -f "${MOK_KEY}" || ! -f "${MOK_CRT}" ]]; then
    skip_or_fail "MOK signing material missing in ${KEY_DIR}"
fi
command -v sbsign >/dev/null 2>&1 || skip_or_fail "sbsign not installed"
command -v sbverify >/dev/null 2>&1 || skip_or_fail "sbverify not installed"

already_signed_by_mok() {
    local f="$1"
    command -v sbverify >/dev/null 2>&1 || return 1
    sbverify --cert "${MOK_CRT}" "${f}" >/dev/null 2>&1
}

sign_one() {
    local f="$1"
    [[ -f "${f}" ]] || { warn "missing: ${f}"; return 1; }
    if already_signed_by_mok "${f}"; then
        log "already MOK-signed: ${f}"
        return 0
    fi
    local tmp="${f}.mok-signed"
    if sbsign --key "${MOK_KEY}" --cert "${MOK_CRT}" --output "${tmp}" "${f}" 2>/dev/null; then
        # Preserve ownership/permissions of the original.
        cat "${tmp}" > "${f}"
        rm -f "${tmp}"
        if ! already_signed_by_mok "${f}"; then
            warn "signature verification failed for ${f}"
            return 1
        fi
        log "signed with MOK: ${f}"
    else
        rm -f "${tmp}"
        warn "sbsign failed for ${f}"
        return 1
    fi
}

for f in "$@"; do
    sign_one "${f}"
done

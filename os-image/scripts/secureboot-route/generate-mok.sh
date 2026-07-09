#!/usr/bin/env bash
# generate-mok.sh — Create the persistent StrawWU Machine Owner Key (MOK) used to
# sign the custom StrawWU kernel so it boots under UEFI Secure Boot after the user
# enrolls the key once (shim MokManager).
#
# The MOK is intentionally a stable, repo-persisted key: signatures stay valid
# across StrawWU updates so a user only enrolls once. It is a self-owned MOK, not
# a trusted CA — it grants nothing beyond booting StrawWU-signed artifacts on the
# machine where the owner explicitly enrolled it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KEY_DIR="${STRAWWU_MOK_DIR:-${REPO_ROOT}/os-image/keys/secureboot}"
CN="${STRAWWU_MOK_CN:-StrawWU Secure Boot Machine Owner Key}"
DAYS="${STRAWWU_MOK_DAYS:-7300}"

MOK_KEY="${KEY_DIR}/StrawWU-MOK.key"
MOK_CRT="${KEY_DIR}/StrawWU-MOK.crt"   # PEM cert (sbsign)
MOK_CER="${KEY_DIR}/StrawWU-MOK.cer"   # DER cert (mokutil --import)

log() { echo "==> $*" >&2; }

main() {
    command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl required" >&2; exit 1; }
    mkdir -p "${KEY_DIR}"
    chmod 700 "${KEY_DIR}"

    if [[ -f "${MOK_KEY}" && -f "${MOK_CRT}" && -f "${MOK_CER}" ]]; then
        log "MOK already present in ${KEY_DIR} — keeping (stable across builds)"
        return 0
    fi

    log "generating StrawWU MOK (RSA-2048, ${DAYS}d) in ${KEY_DIR}"
    openssl req -new -x509 -newkey rsa:2048 -nodes \
        -keyout "${MOK_KEY}" \
        -out "${MOK_CRT}" \
        -days "${DAYS}" \
        -sha256 \
        -subj "/CN=${CN}/" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=digitalSignature" \
        -addext "extendedKeyUsage=codeSigning,1.3.6.1.4.1.311.10.3.6"
    openssl x509 -in "${MOK_CRT}" -outform DER -out "${MOK_CER}"

    chmod 600 "${MOK_KEY}"
    chmod 644 "${MOK_CRT}" "${MOK_CER}"
    log "MOK created: $(basename "${MOK_KEY}"), $(basename "${MOK_CRT}"), $(basename "${MOK_CER}")"
}

main "$@"

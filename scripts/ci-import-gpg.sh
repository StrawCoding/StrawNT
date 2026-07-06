#!/usr/bin/env bash
# ci-import-gpg.sh — import StrawWU release signing key in CI (self-hosted / Actions).
set -euo pipefail

log() { echo "==> $*" >&2; }
warn() { echo "WARN: $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--check]

Import GPG secret key from environment for release / APT signing in CI.

Environment:
  STRAWWU_GPG_PRIVATE_KEY   Armored private key (required for import)
  STRAWWU_GPG_KEY_ID        Key id/fingerprint (optional; auto-detect after import)
  GNUPGHOME                 GPG home (default: ~/.gnupg)

Modes:
  --check   Verify key material is present without importing
EOF
}

check_only=false
if [[ "${1:-}" == "--check" ]]; then
    check_only=true
fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${check_only}" == true ]]; then
    if [[ -n "${STRAWWU_GPG_PRIVATE_KEY:-}" ]]; then
        log "STRAWWU_GPG_PRIVATE_KEY is set"
        exit 0
    fi
    warn "STRAWWU_GPG_PRIVATE_KEY not set (nightly/dev may use SHA256-only mode)"
    exit 0
fi

if [[ -z "${STRAWWU_GPG_PRIVATE_KEY:-}" ]]; then
    warn "STRAWWU_GPG_PRIVATE_KEY not set — skipping GPG import"
    exit 0
fi

if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found" >&2
    exit 1
fi

GNUPGHOME="${GNUPGHOME:-${HOME}/.gnupg}"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

key_file="$(mktemp)"
trap 'rm -f "${key_file}"' EXIT
printf '%s\n' "${STRAWWU_GPG_PRIVATE_KEY}" > "${key_file}"

log "Importing StrawWU GPG key"
gpg --batch --import "${key_file}" >/dev/null 2>&1

if [[ -n "${STRAWWU_GPG_KEY_ID:-}" ]]; then
    log "Using STRAWWU_GPG_KEY_ID=${STRAWWU_GPG_KEY_ID}"
else
    detected="$(gpg --list-secret-keys --keyid-format=long 2>/dev/null \
        | awk '/^sec/ { id=$2; sub(/^.*\//, "", id); print id; exit }' || true)"
    if [[ -n "${detected}" ]]; then
        export STRAWWU_GPG_KEY_ID="${detected}"
        log "Auto-detected STRAWWU_GPG_KEY_ID=${STRAWWU_GPG_KEY_ID}"
    fi
fi

log "GPG import complete"

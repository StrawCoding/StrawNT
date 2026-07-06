#!/usr/bin/env bash
# build-deb.sh — Build strawwu-keyring .deb (APT archive public key).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"
KEYRING_DEST="${PKG_DIR}/usr/share/keyrings/strawwu-archive-keyring.gpg"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

install_keyring() {
    mkdir -p "$(dirname "${KEYRING_DEST}")"

    if [[ -n "${STRAWWU_KEYRING_GPG:-}" ]]; then
        [[ -f "${STRAWWU_KEYRING_GPG}" ]] || die "STRAWWU_KEYRING_GPG not found: ${STRAWWU_KEYRING_GPG}"
        cp -a "${STRAWWU_KEYRING_GPG}" "${KEYRING_DEST}"
        return
    fi

    if [[ -n "${STRAWWU_GPG_KEY_ID:-}" ]] && command -v gpg >/dev/null 2>&1; then
        local key="${STRAWWU_GPG_KEY_ID}"
        key="${key##*/}"
        gpg --batch --yes --export "${key}" | gpg --dearmor > "${KEYRING_DEST}"
        return
    fi

    local default_key="${SCRIPT_DIR}/keys/strawwu-archive-test.pub"
    [[ -f "${default_key}" ]] || die "no key source — set STRAWWU_KEYRING_GPG or STRAWWU_GPG_KEY_ID"
    gpg --dearmor -o "${KEYRING_DEST}" < "${default_key}"
}

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN"
sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${PKG_DIR}/DEBIAN/control"

install_keyring
chmod 644 "${KEYRING_DEST}"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-keyring"
cat > "${PKG_DIR}/usr/share/doc/strawwu-keyring/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-keyring
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-keyring_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

log "Built ${DEB_FILE}"
ls -lh "${DEB_FILE}"

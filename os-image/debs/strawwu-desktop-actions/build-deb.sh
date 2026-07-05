#!/usr/bin/env bash
# build-deb.sh — Build strawwu-desktop-actions .deb (Python + app-registry CLI).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
COMPONENTS_DIR="${REPO_ROOT}/components"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/bin"
mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-desktop-actions"

echo "=== Building strawwu-desktop-actions ${VERSION} ==="

if ! command -v cargo >/dev/null 2>&1; then
    echo "ERROR: cargo not found — install Rust toolchain to build strawwu-app-registry" >&2
    exit 1
fi

cd "${COMPONENTS_DIR}"
cargo build --release --package strawwu-app-registry

REGISTRY_BIN="${COMPONENTS_DIR}/target/release/strawwu-app-registry"
[[ -f "${REGISTRY_BIN}" ]] || { echo "ERROR: strawwu-app-registry missing at ${REGISTRY_BIN}" >&2; exit 1; }

cp "${REGISTRY_BIN}" "${PKG_DIR}/usr/bin/strawwu-app-registry"
strip "${PKG_DIR}/usr/bin/strawwu-app-registry" 2>/dev/null || true
chmod 755 "${PKG_DIR}/usr/bin/strawwu-app-registry"

cp -a "${SCRIPT_DIR}/usr" "${PKG_DIR}/"
chmod 755 "${PKG_DIR}/usr/bin/strawwu-desktop-remove"
chmod 755 "${PKG_DIR}/usr/share/nautilus/scripts/Remove from StrawWU"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

cp "${SCRIPT_DIR}/usr/share/doc/strawwu-desktop-actions/README" "${PKG_DIR}/usr/share/doc/strawwu-desktop-actions/"

cat > "${PKG_DIR}/usr/share/doc/strawwu-desktop-actions/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-desktop-actions
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-desktop-actions_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

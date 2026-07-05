#!/usr/bin/env bash
# build-deb.sh — Build strawwu-wincompat .deb (strawwu CLI from components workspace).
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
mkdir -p "${PKG_DIR}/usr/share/strawwu/wincompat"
mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-wincompat"

echo "=== Building strawwu-wincompat ${VERSION} ==="

if ! command -v cargo >/dev/null 2>&1; then
    echo "ERROR: cargo not found — install Rust toolchain to build strawwu CLI" >&2
    exit 1
fi

cd "${COMPONENTS_DIR}"
cargo build --release --bin strawwu

BINARY="${COMPONENTS_DIR}/target/release/strawwu"
[[ -f "${BINARY}" ]] || { echo "ERROR: strawwu binary missing at ${BINARY}" >&2; exit 1; }

cp "${BINARY}" "${PKG_DIR}/usr/bin/strawwu"
strip "${PKG_DIR}/usr/bin/strawwu" 2>/dev/null || true
chmod 755 "${PKG_DIR}/usr/bin/strawwu"

cp -a "${SCRIPT_DIR}/usr/share/strawwu/wincompat/"* "${PKG_DIR}/usr/share/strawwu/wincompat/"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

cat > "${PKG_DIR}/usr/share/doc/strawwu-wincompat/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-components
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-wincompat_${VERSION}_amd64.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

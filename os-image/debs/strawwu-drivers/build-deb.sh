#!/usr/bin/env bash
# build-deb.sh — Build strawwu-drivers .deb (GPU driver manager CLI).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN"

echo "=== Building strawwu-drivers ${VERSION} ==="

cp -a "${SCRIPT_DIR}/usr" "${PKG_DIR}/"
chmod 755 "${PKG_DIR}/usr/bin/strawwu-drivers"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/DEBIAN/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/DEBIAN/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-drivers"
cat > "${PKG_DIR}/usr/share/doc/strawwu-drivers/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-drivers
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-drivers_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

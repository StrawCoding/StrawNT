#!/usr/bin/env bash
# build-deb.sh — Build strawwu-registry-hooks .deb (APT + Flatpak install hooks).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN"

echo "=== Building strawwu-registry-hooks ${VERSION} ==="

cp -a "${SCRIPT_DIR}/usr" "${SCRIPT_DIR}/etc" "${PKG_DIR}/"
chmod 755 "${PKG_DIR}/usr/bin/strawwu-registry-scan"
chmod 755 "${PKG_DIR}/usr/lib/strawwu-registry-hooks/apt-post-invoke"
chmod 755 "${PKG_DIR}/usr/share/flatpak/triggers/strawwu-registry-scan"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-registry-hooks"
cp "${SCRIPT_DIR}/usr/share/doc/strawwu-registry-hooks/README" \
    "${PKG_DIR}/usr/share/doc/strawwu-registry-hooks/"

cat > "${PKG_DIR}/usr/share/doc/strawwu-registry-hooks/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-registry-hooks
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-registry-hooks_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

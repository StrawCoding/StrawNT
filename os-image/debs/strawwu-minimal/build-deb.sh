#!/usr/bin/env bash
# build-deb.sh — Build strawwu-minimal meta .deb.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" \
    "${PKG_DIR}/DEBIAN" \
    "${PKG_DIR}/usr/share/doc/strawwu-minimal" \
    "${PKG_DIR}/usr/share/strawwu/meta-audit"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

cp "${SCRIPT_DIR}/usr/share/doc/strawwu-minimal/README" "${PKG_DIR}/usr/share/doc/strawwu-minimal/"
cp "${SCRIPT_DIR}/usr/share/strawwu/meta-audit/meta-audit-manifest.yaml" \
    "${PKG_DIR}/usr/share/strawwu/meta-audit/"

cat > "${PKG_DIR}/usr/share/doc/strawwu-minimal/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-minimal
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-minimal_${VERSION}_amd64.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

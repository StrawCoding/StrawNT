#!/usr/bin/env bash
# build-deb.sh — Build strawwu-session .deb from usr/ + etc/ + debian/ templates.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

cp -a "${SCRIPT_DIR}/usr" "${SCRIPT_DIR}/etc" "${PKG_DIR}/"
chmod 755 "${PKG_DIR}/usr/bin/strawwu-session"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-session"
cat > "${PKG_DIR}/usr/share/doc/strawwu-session/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-session
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-session_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

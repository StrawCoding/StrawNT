#!/usr/bin/env bash
# build-deb.sh — Build strawwu-bug-reporter .deb from usr/ + debian/ templates.
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

cp -a "${SCRIPT_DIR}/usr" "${PKG_DIR}/"
chmod 755 "${PKG_DIR}/usr/bin/strawwu-bug-report" "${PKG_DIR}/usr/bin/strawwu-bug-report-gtk"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-bug-reporter"
mkdir -p "${PKG_DIR}/usr/share/applications"
cat > "${PKG_DIR}/usr/share/doc/strawwu-bug-reporter/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-bug-reporter
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

cat > "${PKG_DIR}/usr/share/applications/strawwu-bug-report-gtk.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=StrawWU Bug Report
Comment=Create a local diagnostic bug bundle
Exec=strawwu-bug-report-gtk
Icon=dialog-warning
Categories=System;Settings;
Keywords=bug;report;strawwu;
StartupNotify=true
NoDisplay=false
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-bug-reporter_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

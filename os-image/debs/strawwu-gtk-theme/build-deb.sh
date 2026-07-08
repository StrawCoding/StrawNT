#!/usr/bin/env bash
# build-deb.sh — Build strawwu-gtk-theme .deb (StrawWU-Dark GTK + GNOME Shell).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"
THEME_SRC="${REPO_ROOT}/os-image/config/branding/usr/share/themes/StrawWU-Dark"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

[[ -d "${THEME_SRC}" ]] || { echo "ERROR: theme source missing: ${THEME_SRC}" >&2; exit 1; }

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN" "${PKG_DIR}/usr/share/themes"

echo "=== Building strawwu-gtk-theme ${VERSION} ==="

cp -a "${THEME_SRC}" "${PKG_DIR}/usr/share/themes/"
cp -a "${SCRIPT_DIR}/usr" "${PKG_DIR}/"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/DEBIAN/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/DEBIAN/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-gtk-theme"
cat > "${PKG_DIR}/usr/share/doc/strawwu-gtk-theme/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-gtk-theme
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-gtk-theme_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

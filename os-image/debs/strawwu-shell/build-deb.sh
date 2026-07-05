#!/usr/bin/env bash
# build-deb.sh — Build strawwu-shell .deb (GNOME Shell fork profile + built-in dock).
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
chmod 755 "${PKG_DIR}/usr/bin/strawwu-shell"

sed "s/__VERSION__/${VERSION}/" \
    "${SCRIPT_DIR}/usr/share/strawwu/shell/shell.yaml" \
    > "${PKG_DIR}/usr/share/strawwu/shell/shell.yaml"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-shell"
cat > "${PKG_DIR}/usr/share/doc/strawwu-shell/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-shell
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: GPL-3.0-or-later

Files: usr/share/gnome-shell/extensions/strawwu-dock@strawwu/*
Copyright: 2026 StrawCoding
License: GPL-3.0-or-later
Comment: Cleanroom built-in dock; not a public third-party extension API.
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-shell_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

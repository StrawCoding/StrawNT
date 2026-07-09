#!/usr/bin/env bash
# build-deb.sh — Build strawwu-device-proxy .deb (udev rules + manifest).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/lib/udev/rules.d"
mkdir -p "${PKG_DIR}/usr/lib/strawwu-device-proxy"
mkdir -p "${PKG_DIR}/usr/share/strawwu/device-proxy"
mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-device-proxy"

echo "=== Building strawwu-device-proxy ${VERSION} ==="

cp "${SCRIPT_DIR}/usr/lib/udev/rules.d/99-strawwu-device-proxy.rules" \
    "${PKG_DIR}/usr/lib/udev/rules.d/"
cp "${SCRIPT_DIR}/usr/lib/strawwu-device-proxy/hotplug-notify.sh" \
    "${PKG_DIR}/usr/lib/strawwu-device-proxy/"
chmod 755 "${PKG_DIR}/usr/lib/strawwu-device-proxy/hotplug-notify.sh"

cp -a "${SCRIPT_DIR}/usr/share/strawwu/device-proxy/"* \
    "${PKG_DIR}/usr/share/strawwu/device-proxy/"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/DEBIAN/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/DEBIAN/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"
cp "${SCRIPT_DIR}/DEBIAN/postrm" "${PKG_DIR}/DEBIAN/postrm"
chmod 755 "${PKG_DIR}/DEBIAN/postrm"

cat > "${PKG_DIR}/usr/share/doc/strawwu-device-proxy/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-device-proxy
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-device-proxy_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

#!/usr/bin/env bash
# build-deb.sh — Build strawwu-calamares-settings .deb from etc/ + usr/ templates.
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

cp -a "${SCRIPT_DIR}/etc" "${SCRIPT_DIR}/usr" "${PKG_DIR}/"

mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-calamares-settings"
cat > "${PKG_DIR}/usr/share/doc/strawwu-calamares-settings/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-calamares-settings
Source: https://github.com/StrawCoding/StrawWU

Files: etc/calamares/modules/mount.conf etc/calamares/modules/fstab.conf
 etc/calamares/modules/grubcfg.conf etc/calamares/modules/machineid.conf
 etc/calamares/modules/before_bootloader*.conf etc/calamares/modules/finished.conf
 etc/calamares/modules/umount.conf etc/calamares/modules/shellprocess_*.conf
 usr/libexec/fixconkeys-* usr/lib/x86_64-linux-gnu/calamares/modules/*
Copyright: Canonical Ltd. (upstream calamares-settings-ubuntu-common)
License: GPL-2+

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-calamares-settings_${VERSION}_all.deb"
dpkg-deb --build "${PKG_DIR}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

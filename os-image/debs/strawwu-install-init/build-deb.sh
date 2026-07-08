#!/usr/bin/env bash
# build-deb.sh — Build strawwu-install-init meta .deb.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PKG_DIR="$(mktemp -d)"
LANG_SRC="${SCRIPT_DIR}/usr/share/calamares/branding/strawwu/lang"

cleanup() { rm -rf "${PKG_DIR}"; }
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" "${PKG_DIR}/DEBIAN" "${PKG_DIR}/usr/share/strawwu/install-init" \
    "${PKG_DIR}/usr/share/doc/strawwu-install-init" \
    "${PKG_DIR}/usr/share/calamares/branding/strawwu/lang"

sed "s/__VERSION__/${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${PKG_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${PKG_DIR}/DEBIAN/postinst"
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

cp "${SCRIPT_DIR}/usr/share/strawwu/install-init/install-init-manifest.yaml" \
    "${PKG_DIR}/usr/share/strawwu/install-init/"
if [[ -f "${SCRIPT_DIR}/usr/share/doc/strawwu-install-init/README" ]]; then
    cp "${SCRIPT_DIR}/usr/share/doc/strawwu-install-init/README" \
        "${PKG_DIR}/usr/share/doc/strawwu-install-init/"
fi

LRELEASE=""
for candidate in lrelease-qt6 lrelease lrelease-qt5; do
    if command -v "${candidate}" >/dev/null 2>&1; then
        LRELEASE="${candidate}"
        break
    fi
done
[[ -n "${LRELEASE}" ]] || { echo "ERROR: lrelease required" >&2; exit 1; }

shopt -s nullglob
ts_files=("${LANG_SRC}"/calamares-strawwu_*.ts)
[[ ${#ts_files[@]} -gt 0 ]] || { echo "ERROR: missing branding .ts under ${LANG_SRC}" >&2; exit 1; }
for ts in "${ts_files[@]}"; do
    base="$(basename "${ts}" .ts)"
    "${LRELEASE}" "${ts}" -qm "${PKG_DIR}/usr/share/calamares/branding/strawwu/lang/${base}.qm"
done

cat > "${PKG_DIR}/usr/share/doc/strawwu-install-init/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-install-init
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-install-init_${VERSION}_all.deb"
# Build in /tmp — preflight tests rm -rf output/ in parallel (race-safe).
DEB_TMP="$(mktemp "/tmp/strawwu-install-init_${VERSION}.XXXXXX.deb")"
dpkg-deb --build "${PKG_DIR}" "${DEB_TMP}"
mkdir -p "${OUTPUT_DIR}"
mv -f "${DEB_TMP}" "${DEB_FILE}"

echo "=== Built ${DEB_FILE} ==="
ls -lh "${DEB_FILE}"

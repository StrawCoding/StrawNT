#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPONENTS_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${STRAWWU_VERSION:-0.3.0}"
OUTPUT_DIR="${COMPONENTS_DIR}/packaging/output"

mkdir -p "$OUTPUT_DIR"

echo "=== Building strawwu-components ${VERSION} ==="

cd "$COMPONENTS_DIR"
cargo build --release --workspace

BINARY="${COMPONENTS_DIR}/target/release/strawwu"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: strawwu binary not found at $BINARY"
    exit 1
fi

PKG_DIR=$(mktemp -d)
trap 'rm -rf "$PKG_DIR"' EXIT

mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/bin"
mkdir -p "${PKG_DIR}/usr/lib/strawwu"
mkdir -p "${PKG_DIR}/usr/share/doc/strawwu-launcher"

cp "$BINARY" "${PKG_DIR}/usr/bin/strawwu"
strip "${PKG_DIR}/usr/bin/strawwu" 2>/dev/null || true

cat > "${PKG_DIR}/DEBIAN/control" <<EOF
Package: strawwu-launcher
Version: ${VERSION}-1
Architecture: amd64
Maintainer: StrawCoding <dev@strawcoding.org>
Depends: libc6 (>= 2.35)
Section: utils
Priority: optional
Description: StrawWU application launcher
 CLI tool (strawwu) for launching PE/ELF binaries in the
 StrawWU runtime environment with SubsystemSession support.
EOF

cat > "${PKG_DIR}/usr/share/doc/strawwu-launcher/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: strawwu-components
Source: https://github.com/StrawCoding/StrawWU

Files: *
Copyright: 2026 StrawCoding
License: MIT
EOF

DEB_FILE="${OUTPUT_DIR}/strawwu-launcher_${VERSION}-1_amd64.deb"
dpkg-deb --build "$PKG_DIR" "$DEB_FILE"

echo "=== Package built: $DEB_FILE ==="
echo "  Size: $(du -h "$DEB_FILE" | cut -f1)"

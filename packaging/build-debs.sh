#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(cat "$REPO_ROOT/VERSION")}"
OUTPUT_DIR="${REPO_ROOT}/packaging/output"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "=== Building StrawWU .deb packages v${VERSION} ==="

# --- strawwu-branding ---
echo "[1/3] strawwu-branding"
BRAND_PKG="/tmp/strawwu-branding-build"
rm -rf "$BRAND_PKG"
mkdir -p "$BRAND_PKG/DEBIAN"

BRANDING="$REPO_ROOT/os-image/config/branding"

# Copy entire branding tree (etc/, usr/) into package root
for subdir in etc usr; do
    if [ -d "$BRANDING/$subdir" ]; then
        cp -a "$BRANDING/$subdir" "$BRAND_PKG/"
    fi
done

# Add logo icons
mkdir -p "$BRAND_PKG/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$BRAND_PKG/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$BRAND_PKG/usr/share/pixmaps"
cp "$BRANDING/logo-icon.svg" "$BRAND_PKG/usr/share/icons/hicolor/scalable/apps/strawwu.svg" 2>/dev/null || true
cp "$BRANDING/logo-icon-256.png" "$BRAND_PKG/usr/share/icons/hicolor/256x256/apps/strawwu.png" 2>/dev/null || true
cp "$BRANDING/logo-icon-64.png" "$BRAND_PKG/usr/share/pixmaps/strawwu.png" 2>/dev/null || true

sed "s/__VERSION__/${VERSION}/" "$REPO_ROOT/packaging/strawwu-branding/DEBIAN/control" > "$BRAND_PKG/DEBIAN/control"
cp "$REPO_ROOT/packaging/strawwu-branding/DEBIAN/postinst" "$BRAND_PKG/DEBIAN/postinst"
chmod 755 "$BRAND_PKG/DEBIAN/postinst"

dpkg-deb --build "$BRAND_PKG" "$OUTPUT_DIR/strawwu-branding_${VERSION}_all.deb"

# --- strawwu-hub ---
echo "[2/3] strawwu-hub (electron-builder)"
cd "$REPO_ROOT/hub"
if [ ! -d "node_modules" ]; then
    npm ci
fi
npx electron-builder --linux deb --publish never 2>&1 | tail -5
HUB_DEB=$(find dist -name "*.deb" -type f | head -1)
if [ -n "$HUB_DEB" ]; then
    cp "$HUB_DEB" "$OUTPUT_DIR/strawwu-hub_${VERSION}_amd64.deb"
else
    echo "WARNING: Hub .deb not found, skipping"
fi
cd "$REPO_ROOT"

# --- strawwu-system (meta) ---
echo "[3/3] strawwu-system"
META_PKG="/tmp/strawwu-system-build"
rm -rf "$META_PKG"
mkdir -p "$META_PKG/DEBIAN"

sed "s/__VERSION__/${VERSION}/g" "$REPO_ROOT/packaging/strawwu-system/DEBIAN/control" > "$META_PKG/DEBIAN/control"
dpkg-deb --build "$META_PKG" "$OUTPUT_DIR/strawwu-system_${VERSION}_all.deb"

# Kernel .deb (108MB+) is too large for GitHub Pages APT repo.
# It ships with the ISO and rarely needs separate updates.
echo "[i] Kernel .deb skipped (ships with ISO)"

echo ""
echo "=== Done ==="
ls -lh "$OUTPUT_DIR/"

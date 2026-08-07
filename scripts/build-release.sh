#!/usr/bin/env bash
# build-release.sh — StrawNT NTW7 release artefacts: .deb + .rpm (+ flatpak PARTIAL marker)
# powered by Wine · execution_backend=wine · engine=proton-ge
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

parse_deb_version() {
  local a b c d
  IFS=. read -r a b c d <<< "$1"
  if [[ "${d}" == "0" ]]; then
    echo "${a}.${b}.${c}"
  else
    echo "${a}.${b}.${c}+d${d}"
  fi
}

DEB_VER="$(parse_deb_version "${VERSION}")"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
DIST="${REPO_ROOT}/dist"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/strawnt-pkg.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[build-release] $*" >&2; }

command -v cargo >/dev/null || die "cargo required"
command -v dpkg-deb >/dev/null || die "dpkg-deb required"
command -v fakeroot >/dev/null || die "fakeroot required"
command -v docker >/dev/null || die "docker required for rpm build"
command -v rsync >/dev/null || die "rsync required"

mkdir -p "${DIST}"
rm -f "${DIST}"/strawnt_*.deb "${DIST}"/strawnt-*.rpm \
  "${DIST}/SHA256SUMS" "${DIST}/SHA256SUMS.asc" \
  "${DIST}/flatpak-status.json" "${DIST}/sign-result.json" 2>/dev/null || true
rm -f "${REPO_ROOT}/SHA256SUMS" "${REPO_ROOT}/SHA256SUMS.asc" 2>/dev/null || true

log "building release strawnt ${VERSION} (deb_ver=${DEB_VER})"

# --- release binary (build on bookworm glibc so deb works on Debian 12 + Ubuntu 24.04) ---
PKG_TARGET="${REPO_ROOT}/components/target-pkg"
mkdir -p "${PKG_TARGET}"
log "cargo build --release --bin strawnt (docker rust:1-bookworm → ${PKG_TARGET})"
docker run --rm \
  -v "${REPO_ROOT}:/src:rw" \
  -v "${HOME}/.cargo/registry:/usr/local/cargo/registry:rw" \
  -v "${HOME}/.cargo/git:/usr/local/cargo/git:rw" \
  -e CARGO_TARGET_DIR=/src/components/target-pkg \
  -w /src/components \
  rust:1-bookworm \
  cargo build --release --bin strawnt
BINARY="${PKG_TARGET}/release/strawnt"
[[ -x "${BINARY}" ]] || die "missing ${BINARY}"
# Quick self-check on host (host glibc is newer — OK)
"${BINARY}" doctor --json >/dev/null || die "release strawnt missing doctor (stale binary?)"
log "packaged binary glibc baseline: debian bookworm (rust:1-bookworm)"

ROOTFS="${STAGE}/rootfs"
LIB="${ROOTFS}/usr/lib/strawnt"
BIN="${ROOTFS}/usr/bin"
SHARE_APP="${ROOTFS}/usr/share/applications"
SHARE_MIME="${ROOTFS}/usr/share/mime/packages"
SHARE_DOC="${ROOTFS}/usr/share/doc/strawnt"
SHARE_META="${ROOTFS}/usr/share/metainfo"
mkdir -p "${LIB}" "${BIN}" "${SHARE_APP}" "${SHARE_MIME}" "${SHARE_DOC}" \
  "${SHARE_META}" "${ROOTFS}/DEBIAN" \
  "${LIB}/packaging/desktop" "${LIB}/packaging/mime" "${LIB}/packaging/hub" \
  "${LIB}/packaging/flatpak" "${LIB}/hub" \
  "${LIB}/third_party/proton-ge" "${LIB}/scripts" "${LIB}/docs/legal"

mkdir -p "${LIB}/bin"
install -m 0755 "${BINARY}" "${LIB}/bin/strawnt-real"
strip "${LIB}/bin/strawnt-real" 2>/dev/null || true

# Product tree pieces needed at runtime / honesty
printf '%s\n' "${VERSION}" > "${LIB}/VERSION"
install -m 0644 "${REPO_ROOT}/third_party/proton-ge/PIN" "${LIB}/third_party/proton-ge/PIN"
install -m 0644 "${REPO_ROOT}/third_party/proton-ge/README.md" "${LIB}/third_party/proton-ge/README.md"
install -m 0644 "${REPO_ROOT}/THIRD_PARTY_NOTICES" "${LIB}/THIRD_PARTY_NOTICES"
install -m 0644 "${REPO_ROOT}/docs/legal/WINE-LGPL.md" "${LIB}/docs/legal/WINE-LGPL.md"
install -m 0644 "${REPO_ROOT}/LICENSE" "${SHARE_DOC}/copyright" 2>/dev/null \
  || printf 'MIT — see repo LICENSE\n' > "${SHARE_DOC}/copyright"
install -m 0644 "${REPO_ROOT}/README.md" "${SHARE_DOC}/README.md"
install -m 0755 "${REPO_ROOT}/scripts/fetch-proton-ge.sh" "${LIB}/scripts/fetch-proton-ge.sh"
install -m 0755 "${REPO_ROOT}/scripts/verify-proton-ge.sh" "${LIB}/scripts/verify-proton-ge.sh"

# Hub sources for gui_local + vendored Electron runtime (required for post-install GUI)
rsync -a \
  --exclude 'node_modules/' \
  --exclude 'dist/' \
  --exclude 'test/' \
  --exclude 'tests/' \
  --exclude 'package-lock.json' \
  "${REPO_ROOT}/hub/" "${LIB}/hub/"
# Desktop entries for system apps (gui_local)
mkdir -p "${LIB}/hub/resources/desktop"
rsync -a "${REPO_ROOT}/hub/resources/desktop/" "${LIB}/hub/resources/desktop/"

log "vendoring Electron runtime into package (gui_local)"
ELE_SRC=""
if [[ -x "${REPO_ROOT}/hub/node_modules/electron/dist/electron" ]]; then
  ELE_SRC="${REPO_ROOT}/hub/node_modules/electron/dist"
  log "reusing host hub/node_modules/electron/dist"
else
  command -v npm >/dev/null || die "npm required to vendor Electron for gui_local"
  HUB_BUILD="${STAGE}/hub-build"
  rm -rf "${HUB_BUILD}"
  mkdir -p "${HUB_BUILD}"
  rsync -a \
    --exclude 'node_modules/' \
    --exclude 'dist/' \
    --exclude 'test/' \
    --exclude 'tests/' \
    "${REPO_ROOT}/hub/" "${HUB_BUILD}/"
  (
    cd "${HUB_BUILD}"
    if [[ -f package-lock.json ]]; then
      npm ci
    else
      npm install
    fi
  )
  ELE_SRC="${HUB_BUILD}/node_modules/electron/dist"
fi
[[ -x "${ELE_SRC}/electron" ]] || die "electron binary missing (${ELE_SRC})"
mkdir -p "${LIB}/hub/electron-runtime"
rsync -a "${ELE_SRC}/" "${LIB}/hub/electron-runtime/"
chmod 0755 "${LIB}/hub/electron-runtime/electron"
if [[ -f "${LIB}/hub/electron-runtime/chrome-sandbox" ]]; then
  chmod 0755 "${LIB}/hub/electron-runtime/chrome-sandbox"
fi
ELE_VER="$(tr -d '[:space:]' < "${LIB}/hub/electron-runtime/version" 2>/dev/null || echo unknown)"
printf '%s\n' "${ELE_VER}" > "${LIB}/hub/electron-runtime/ELECTRON_VERSION"
log "bundled Electron ${ELE_VER} → /usr/lib/strawnt/hub/electron-runtime/"

install -m 0644 "${REPO_ROOT}/packaging/hub/strawnt-hub-entry.json" "${LIB}/packaging/hub/"
install -m 0644 "${REPO_ROOT}/packaging/mime/strawnt-win32.xml" "${LIB}/packaging/mime/"
install -m 0644 "${REPO_ROOT}/packaging/flatpak/org.strawcoding.strawnt.yml" "${LIB}/packaging/flatpak/"
install -m 0644 "${REPO_ROOT}/packaging/flatpak/SANDBOX-NOTES.md" "${LIB}/packaging/flatpak/"
rsync -a "${REPO_ROOT}/packaging/desktop/" "${LIB}/packaging/desktop/"

cat > "${LIB}/third_party/proton-ge/ENGINE-NOTE.txt" <<'EOF'
StrawNT packages ship the Proton-GE PIN + fetch/verify scripts, not the full
multi-GB dist tree (git-lfs). Place or fetch the engine here:

  /usr/lib/strawnt/third_party/proton-ge/dist/...

  STRAWNT_ROOT=/usr/lib/strawnt bash /usr/lib/strawnt/scripts/fetch-proton-ge.sh

execution_backend=wine · engine=proton-ge · powered by Wine
EOF

# CLI wrapper — pins STRAWNT_ROOT
cat > "${BIN}/strawnt" <<'EOF'
#!/usr/bin/env bash
# StrawNT launcher — powered by Wine · execution_backend=wine · engine=proton-ge
set -euo pipefail
export STRAWNT_ROOT="${STRAWNT_ROOT:-/usr/lib/strawnt}"
exec "${STRAWNT_ROOT}/bin/strawnt-real" "$@"
EOF
chmod 0755 "${BIN}/strawnt"

# Hub / gui_local wrapper — prefers packaged Electron runtime
cat > "${BIN}/strawnt-hub" <<'EOF'
#!/usr/bin/env bash
# StrawNT Electron Hub (gui_local) — powered by Wine · execution_backend=wine
set -euo pipefail
export STRAWNT_ROOT="${STRAWNT_ROOT:-/usr/lib/strawnt}"
HUB_DIR="${STRAWNT_ROOT}/hub"
BUNDLE_ELE="${HUB_DIR}/electron-runtime/electron"
export PATH="${STRAWNT_ROOT}/bin:${PATH}"

if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "version" ]]; then
  ELE_VER="$(tr -d '[:space:]' < "${HUB_DIR}/electron-runtime/version" 2>/dev/null || echo missing)"
  echo "strawnt-hub $(tr -d '[:space:]' < "${STRAWNT_ROOT}/VERSION" 2>/dev/null || echo unknown) (gui_local; electron=${ELE_VER}; powered by Wine)"
  exit 0
fi

pick_electron() {
  # 1) Packaged runtime (deb/rpm must ship this for gui_local PASS)
  if [[ -x "${BUNDLE_ELE}" ]]; then
    echo "${BUNDLE_ELE}"
    return 0
  fi
  # 2) Dev / system fallbacks
  if [[ -x "${HUB_DIR}/node_modules/electron/dist/electron" ]]; then
    echo "${HUB_DIR}/node_modules/electron/dist/electron"
    return 0
  fi
  if [[ -x "${HUB_DIR}/node_modules/.bin/electron" ]]; then
    echo "${HUB_DIR}/node_modules/.bin/electron"
    return 0
  fi
  if command -v electron >/dev/null 2>&1; then
    command -v electron
    return 0
  fi
  return 1
}

ELE_ARGS=()
# Chromium refuses root without --no-sandbox (CI / container smoke)
if [[ "$(id -u)" -eq 0 ]] || [[ "${STRAWNT_ELECTRON_NO_SANDBOX:-0}" == "1" ]]; then
  ELE_ARGS+=(--no-sandbox)
fi

if ELE="$(pick_electron)"; then
  exec "${ELE}" "${ELE_ARGS[@]}" "${HUB_DIR}" "$@"
fi

cat >&2 <<MSG
strawnt-hub: Electron runtime not found.
Expected packaged binary: ${BUNDLE_ELE}
MSG
exit 127
EOF
chmod 0755 "${BIN}/strawnt-hub"

# Desktop files
for tmpl in strawnt.desktop.in strawnt-open.desktop.in; do
  out="${SHARE_APP}/${tmpl%.in}"
  sed 's|@STRAWNT_BIN@|/usr/bin/strawnt|g' \
    "${REPO_ROOT}/packaging/desktop/${tmpl}" > "${out}"
  chmod 0644 "${out}"
done
sed -e 's|@STRAWNT_HUB_BIN@|/usr/bin/strawnt-hub|g' \
  "${REPO_ROOT}/packaging/desktop/strawnt-hub.desktop.in" \
  > "${SHARE_APP}/strawnt-hub.desktop"
chmod 0644 "${SHARE_APP}/strawnt-hub.desktop"

# Also ship dedicated system-app desktops (gui_local suite)
for desk in "${REPO_ROOT}/hub/resources/desktop/"*.desktop; do
  [[ -f "${desk}" ]] || continue
  base="$(basename "${desk}")"
  install -m 0644 "${desk}" "${SHARE_APP}/${base}"
done

install -m 0644 "${REPO_ROOT}/packaging/mime/strawnt-win32.xml" \
  "${SHARE_MIME}/strawnt-win32.xml"

cat > "${SHARE_META}/org.strawcoding.strawnt.metainfo.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>org.strawcoding.strawnt</id>
  <name>StrawNT</name>
  <summary>Windows apps on Linux via Wine/Proton-GE — powered by Wine</summary>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT and LGPL-2.1-or-later</project_license>
  <description>
    <p>StrawNT is a Wine/Proton-GE product shell (execution_backend=wine,
    engine=proton-ge) with Electron Hub, App Manager, and Win32 IPC interop.
    It is not a native PE OS and must say powered by Wine.</p>
  </description>
  <url type="homepage">https://github.com/StrawCoding/StrawNT</url>
  <launchable type="desktop-id">strawnt-hub.desktop</launchable>
  <provides><binary>strawnt</binary></provides>
  <releases>
    <release version="${VERSION}" date="$(date -u +%Y-%m-%d)"/>
  </releases>
  <custom>
    <value key="X-StrawNT-Backend">wine</value>
    <value key="X-StrawNT-Engine">proton-ge</value>
    <value key="X-StrawNT-PoweredBy">Wine</value>
  </custom>
</component>
EOF

cat > "${SHARE_DOC}/README.packaging.txt" <<EOF
StrawNT ${VERSION} package

  /usr/bin/strawnt       CLI wrapper (STRAWNT_ROOT=/usr/lib/strawnt)
  /usr/bin/strawnt-hub   Electron Hub gui_local launcher
  /usr/lib/strawnt/      Product root (PIN, hub sources, Electron runtime, scripts)
  /usr/lib/strawnt/hub/electron-runtime/  Vendored Electron (gui_local)

Fetch Proton-GE engine (not embedded in deb/rpm; multi-GB git-lfs):
  STRAWNT_ROOT=/usr/lib/strawnt /usr/lib/strawnt/scripts/fetch-proton-ge.sh

execution_backend=wine · engine=proton-ge · powered by Wine
Flatpak: PARTIAL (see packaging/flatpak/SANDBOX-NOTES.md)
EOF

# Permissions
find "${ROOTFS}" -type d -exec chmod 0755 {} +
find "${ROOTFS}" -type f -exec chmod go-w {} +
chmod 0755 "${BIN}/strawnt" "${BIN}/strawnt-hub" "${LIB}/bin/strawnt-real"
chmod 0755 "${LIB}/scripts/"*.sh

# --- .deb ---
log "building .deb"
cat > "${ROOTFS}/DEBIAN/control" <<EOF
Package: strawnt
Version: ${DEB_VER}-1
Architecture: ${ARCH}
Maintainer: StrawCoding <dev@strawcoding.org>
Depends: libc6 (>= 2.35), libgtk-3-0, libnss3, libxss1, libxtst6, libasound2 | libasound2t64, libgbm1, libdrm2, libxkbcommon0, libxcomposite1, libxdamage1, libxfixes3, libxrandr2, libpango-1.0-0, libcairo2, libcups2 | libcups2t64, libatk-bridge2.0-0 | libatk-bridge2.0-0t64, libatk1.0-0 | libatk1.0-0t64
Recommends: libvulkan1, xdg-utils, libnotify4
Section: utils
Priority: optional
Homepage: https://github.com/StrawCoding/StrawNT
Description: StrawNT — Windows apps on Linux, powered by Wine
 Product shell for vendored Proton-GE / Wine (execution_backend=wine).
 Provides CLI, MIME handlers, Electron Hub gui_local (bundled runtime),
 App Manager. Does not claim full Windows or ranked anti-cheat.
 Flatpak is PARTIAL. Proton-GE dist fetched separately (PIN + scripts).
EOF

DEB_NAME="strawnt_${DEB_VER}-1_${ARCH}.deb"
DEB_PATH="${DIST}/${DEB_NAME}"
fakeroot dpkg-deb --build "${ROOTFS}" "${DEB_PATH}"
log "built ${DEB_PATH}"

# --- .rpm via Fedora container ---
log "building .rpm (fedora:41)"
RPM_STAGE="${STAGE}/rpm"
mkdir -p "${RPM_STAGE}/BUILD" "${RPM_STAGE}/RPMS" "${RPM_STAGE}/SOURCES" \
  "${RPM_STAGE}/SPECS" "${RPM_STAGE}/SRPMS" "${RPM_STAGE}/BUILDROOT" \
  "${RPM_STAGE}/rootfs"
# rpm rootfs without DEBIAN/
rsync -a --exclude DEBIAN "${ROOTFS}/" "${RPM_STAGE}/rootfs/"

RPM_VER="${VERSION}"
# RPM dislikes some + in version; use underscores for preview
RPM_VER_SAFE="$(echo "${VERSION}" | tr '+' '_')"
SPEC_OUT="${RPM_STAGE}/SPECS/strawnt.spec"
sed -e "s|@VERSION@|${RPM_VER_SAFE}|g" \
    -e "s|@ROOTFS@|${RPM_STAGE}/rootfs|g" \
    "${REPO_ROOT}/packaging/rpm/strawnt.spec.in" > "${SPEC_OUT}"
# Fix %install to use container-local path
cat > "${SPEC_OUT}" <<EOF
Name: strawnt
Version: ${RPM_VER_SAFE}
Release: 1%{?dist}
Summary: StrawNT — Windows apps on Linux via Wine/Proton-GE
License: MIT AND LGPL-2.1-or-later
URL: https://github.com/StrawCoding/StrawNT
BuildArch: x86_64
Requires: gtk3, nss, libXScrnSaver, libXtst, alsa-lib, mesa-libgbm, libdrm, libxkbcommon, libXcomposite, libXdamage, libXfixes, libXrandr, pango, cairo, cups-libs, at-spi2-atk, atk

%description
StrawNT product shell and CLI (execution_backend=wine, engine=proton-ge).
Powered by Wine. Bundles Electron for gui_local Hub. Does not claim full
Windows or ranked anti-cheat. Proton-GE dist is fetched separately.

%install
mkdir -p %{buildroot}
cp -a /src/rootfs/. %{buildroot}/

%files
/usr/bin/strawnt
/usr/bin/strawnt-hub
/usr/lib/strawnt
/usr/share/applications/*.desktop
/usr/share/mime/packages/strawnt-win32.xml
/usr/share/metainfo/org.strawcoding.strawnt.metainfo.xml
/usr/share/doc/strawnt

%changelog
* Sat Aug 08 2026 StrawCoding <dev@strawcoding.org> - ${RPM_VER_SAFE}-1
- NTW7 packaging: deb/rpm + MIME + gui_local with bundled Electron (powered by Wine)
EOF

docker run --rm \
  -v "${RPM_STAGE}:/src:ro" \
  -v "${DIST}:/out" \
  fedora:41 \
  bash -lc '
    set -euo pipefail
    dnf install -y -q rpm-build >/dev/null
    mkdir -p /root/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
    cp /src/SPECS/strawnt.spec /root/rpmbuild/SPECS/strawnt.spec
    rpmbuild -bb /root/rpmbuild/SPECS/strawnt.spec
    cp -a /root/rpmbuild/RPMS/x86_64/strawnt-*.rpm /out/
  '
RPM_PATH="$(find "${DIST}" -maxdepth 1 -name 'strawnt-*.rpm' | head -1)"
[[ -n "${RPM_PATH}" && -f "${RPM_PATH}" ]] || die "rpm missing after fedora build"
log "built ${RPM_PATH}"

# --- Flatpak honesty marker ---
cat > "${DIST}/flatpak-status.json" <<EOF
{
  "format": "flatpak",
  "status": "PARTIAL",
  "reason": "Flatpak sandbox limits PE/.exe install paths and Wine/Proton-GE prefix UX; StrawNT ships .deb/.rpm as primary. Manifest stub only.",
  "execution_backend": "wine",
  "engine": "proton-ge",
  "powered_by": "Wine",
  "manifest": "packaging/flatpak/org.strawcoding.strawnt.yml",
  "notes": "See packaging/flatpak/SANDBOX-NOTES.md"
}
EOF

log "release artefacts:"
ls -lh "${DIST}"
echo "VERSION=${VERSION} DEB_VER=${DEB_VER}"

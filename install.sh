#!/usr/bin/env bash
# StrawWU Portable Core — one-line installer for generic Linux.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash
#   curl -fsSL ... | bash -s -- --prefix "$HOME/.local/strawwu"
#   curl -fsSL ... | bash -s -- --version 0.7.1.15
#
# Env overrides: STRAWWU_PREFIX, STRAWWU_BIN_DIR, STRAWWU_VERSION, STRAWWU_REPO
set -euo pipefail

REPO="${STRAWWU_REPO:-StrawCoding/StrawWU-portable}"
PREFIX="${STRAWWU_PREFIX:-${HOME}/.local/share/strawwu-core}"
BIN_DIR="${STRAWWU_BIN_DIR:-${HOME}/.local/bin}"
REQUESTED_VERSION="${STRAWWU_VERSION:-}"
ARCH="$(uname -m)"
TMPDIR_ROOT="${TMPDIR:-/tmp}"
WORK=""

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[strawwu-install] $*" >&2; }

usage() {
  cat <<'EOF'
StrawWU Portable Core installer

Options:
  --prefix DIR     Install root (default: ~/.local/share/strawwu-core)
  --bin-dir DIR    Symlink directory (default: ~/.local/bin)
  --version VER    Release tag/version (default: latest GitHub release)
  --help           Show this help

Examples:
  curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash
  curl -fsSL ... | bash -s -- --prefix "$HOME/.local/strawwu"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --bin-dir) BIN_DIR="$2"; shift 2 ;;
    --version) REQUESTED_VERSION="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "Linux only (got $(uname -s))"
[[ "${ARCH}" == "x86_64" || "${ARCH}" == "amd64" ]] || die "unsupported arch: ${ARCH} (need x86_64)"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"

api_get() {
  local url="$1"
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${url}"
}

resolve_release() {
  local json tag asset_url sums_url name
  if [[ -n "${REQUESTED_VERSION}" ]]; then
    local ver="${REQUESTED_VERSION#v}"
    json="$(api_get "https://api.github.com/repos/${REPO}/releases/tags/v${ver}" 2>/dev/null \
      || api_get "https://api.github.com/repos/${REPO}/releases/tags/${ver}")" \
      || die "release not found for version ${REQUESTED_VERSION}"
  else
    json="$(api_get "https://api.github.com/repos/${REPO}/releases/latest")" \
      || die "failed to fetch latest release from ${REPO}"
  fi

  tag="$(printf '%s' "${json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tag_name",""))')"
  [[ -n "${tag}" ]] || die "release has no tag_name"

  # Prefer portable.tar.gz (no FUSE); AppImage is optional fallback.
  read -r asset_url name sums_url < <(printf '%s' "${json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assets = d.get("assets") or []
tgz = next((a for a in assets if a["name"].endswith(".portable.tar.gz")), None)
sums = next((a for a in assets if a["name"] == "SHA256SUMS"), None)
app = next((a for a in assets if a["name"].endswith(".AppImage")), None)
pick = tgz or app
if not pick:
    sys.exit(1)
sums_url = sums["browser_download_url"] if sums else ""
print(pick["browser_download_url"], pick["name"], sums_url)
') || die "release ${tag} has no portable.tar.gz / AppImage asset"

  RELEASE_TAG="${tag}"
  ASSET_URL="${asset_url}"
  ASSET_NAME="${name}"
  SUMS_URL="${sums_url}"
}

cleanup() {
  if [[ -n "${WORK}" && -d "${WORK}" ]]; then
    rm -rf "${WORK}"
  fi
}
trap cleanup EXIT

resolve_release
log "repo=${REPO} release=${RELEASE_TAG} asset=${ASSET_NAME}"
log "prefix=${PREFIX}"
log "bin-dir=${BIN_DIR}"

WORK="$(mktemp -d "${TMPDIR_ROOT}/strawwu-install.XXXXXX")"
ASSET_PATH="${WORK}/${ASSET_NAME}"
log "downloading ${ASSET_URL}"
curl -fL --progress-bar -o "${ASSET_PATH}" "${ASSET_URL}" \
  || die "download failed"

if [[ -n "${SUMS_URL}" ]]; then
  log "verifying SHA256"
  curl -fsSL -o "${WORK}/SHA256SUMS" "${SUMS_URL}" || die "SHA256SUMS download failed"
  (
    cd "${WORK}"
    # Only check the asset we downloaded (SUMS may list multiple files).
    awk -v f="${ASSET_NAME}" '$2 == f { print }' SHA256SUMS > SHA256SUMS.check
    [[ -s SHA256SUMS.check ]] || die "SHA256SUMS has no entry for ${ASSET_NAME}"
    sha256sum -c SHA256SUMS.check
  ) || die "checksum mismatch"
else
  log "WARNING: no SHA256SUMS in release — skipping checksum"
fi

STAGE="${WORK}/stage"
mkdir -p "${STAGE}"
if [[ "${ASSET_NAME}" == *.portable.tar.gz ]]; then
  tar -xzf "${ASSET_PATH}" -C "${STAGE}"
  APPDIR="$(find "${STAGE}" -maxdepth 1 -type d -name 'StrawWU-Core-*-x86_64.AppDir' | head -n1 || true)"
  [[ -n "${APPDIR}" && -x "${APPDIR}/AppRun" ]] || die "portable archive missing AppDir/AppRun"
  SRC_ROOT="${APPDIR}/usr"
elif [[ "${ASSET_NAME}" == *.AppImage ]]; then
  chmod +x "${ASSET_PATH}"
  (
    cd "${STAGE}"
    # Extract without FUSE when possible.
    if "${ASSET_PATH}" --appimage-extract >/dev/null 2>&1; then
      true
    else
      die "AppImage extract failed (try portable.tar.gz release asset)"
    fi
  )
  APPDIR="${STAGE}/squashfs-root"
  [[ -x "${APPDIR}/AppRun" ]] || die "extracted AppImage missing AppRun"
  SRC_ROOT="${APPDIR}/usr"
else
  die "unsupported asset type: ${ASSET_NAME}"
fi

[[ -x "${SRC_ROOT}/bin/strawwu" ]] || die "missing bin/strawwu in artifact"

log "installing into ${PREFIX}"
mkdir -p "${PREFIX}"
# Replace previous install contents but keep the prefix directory itself.
find "${PREFIX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "${SRC_ROOT}/." "${PREFIX}/"
chmod 755 "${PREFIX}/bin/strawwu" 2>/dev/null || true
[[ -x "${PREFIX}/bin/strawwu-env" ]] && chmod 755 "${PREFIX}/bin/strawwu-env" || true

# Wrapper so STRAWWU_PREFIX points at the installed tree.
WRAPPER="${PREFIX}/bin/strawwu-portable"
cat > "${WRAPPER}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export STRAWWU_PREFIX="${PREFIX}"
export STRAWWU_APP_REGISTRY="\${STRAWWU_APP_REGISTRY:-\${STRAWWU_PREFIX}/var/lib/strawwu/app-registry.json}"
export PATH="\${STRAWWU_PREFIX}/bin:\${PATH}"
export LD_LIBRARY_PATH="\${STRAWWU_PREFIX}/lib/strawwu:\${STRAWWU_PREFIX}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "\${STRAWWU_PREFIX}/bin/strawwu" "\$@"
EOF
chmod 755 "${WRAPPER}"

mkdir -p "${BIN_DIR}"
ln -sfn "${WRAPPER}" "${BIN_DIR}/strawwu"

# Smoke
export PATH="${BIN_DIR}:${PATH}"
VER_OUT="$("${BIN_DIR}/strawwu" --version 2>&1 || true)"
[[ -n "${VER_OUT}" ]] || die "post-install --version failed"
STATUS_RC=0
"${BIN_DIR}/strawwu" status >/dev/null 2>&1 || STATUS_RC=$?

cat <<EOF

StrawWU Portable Core installed.

  release : ${RELEASE_TAG}
  prefix  : ${PREFIX}
  command : ${BIN_DIR}/strawwu
  version : ${VER_OUT}
  status  : exit ${STATUS_RC}

Try:
  strawwu --version
  strawwu status

If 'strawwu' is not found, add to PATH:
  export PATH="${BIN_DIR}:\$PATH"

Honest note: this is the portable Win-compat *core* (CLI/runtime).
It does not claim full Windows app compatibility, and it is not the StrawWU ISO/desktop OS.
EOF

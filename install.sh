#!/usr/bin/env bash
# StrawNT — one-line installer for generic Linux (native PE / NT ABI runtime).
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawNT/main/install.sh | bash
#   curl -fsSL ... | bash -s -- --prefix "$HOME/.local/strawnt"
#   curl -fsSL ... | bash -s -- --version 0.7.1.33
#
# Env overrides: STRAWNT_PREFIX, STRAWNT_BIN_DIR, STRAWNT_VERSION, STRAWNT_REPO
# Compat (deprecated): STRAWWU_PREFIX, STRAWWU_BIN_DIR, STRAWWU_VERSION, STRAWWU_REPO
set -euo pipefail

REPO="${STRAWNT_REPO:-${STRAWWU_REPO:-StrawCoding/StrawNT}}"
PREFIX="${STRAWNT_PREFIX:-${STRAWWU_PREFIX:-${HOME}/.local/share/strawnt}}"
BIN_DIR="${STRAWNT_BIN_DIR:-${STRAWWU_BIN_DIR:-${HOME}/.local/bin}}"
REQUESTED_VERSION="${STRAWNT_VERSION:-${STRAWWU_VERSION:-}}"
# Local portable.tar.gz / AppImage bypasses GitHub download (CI / nt6 clean-env).
LOCAL_ASSET="${STRAWNT_LOCAL_ASSET:-}"
ARCH="$(uname -m)"
TMPDIR_ROOT="${TMPDIR:-/tmp}"
WORK=""

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[strawnt-install] $*" >&2; }

usage() {
  cat <<'EOF'
StrawNT installer

Options:
  --prefix DIR     Install root (default: ~/.local/share/strawnt)
  --bin-dir DIR    Symlink directory (default: ~/.local/bin)
  --version VER    Release tag/version (default: latest GitHub release)
  --local FILE     Install from local portable.tar.gz / AppImage
  --help           Show this help

Examples:
  curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawNT/main/install.sh | bash
  curl -fsSL ... | bash -s -- --prefix "$HOME/.local/strawnt"
  STRAWNT_LOCAL_ASSET=./StrawNT-*.portable.tar.gz bash install.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --bin-dir) BIN_DIR="$2"; shift 2 ;;
    --version) REQUESTED_VERSION="$2"; shift 2 ;;
    --local) LOCAL_ASSET="$2"; shift 2 ;;
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

WORK="$(mktemp -d "${TMPDIR_ROOT}/strawnt-install.XXXXXX")"
ASSET_PATH=""
ASSET_NAME=""
RELEASE_TAG=""

if [[ -n "${LOCAL_ASSET}" ]]; then
  [[ -f "${LOCAL_ASSET}" ]] || die "local asset not found: ${LOCAL_ASSET}"
  ASSET_NAME="$(basename "${LOCAL_ASSET}")"
  ASSET_PATH="${WORK}/${ASSET_NAME}"
  cp -a "${LOCAL_ASSET}" "${ASSET_PATH}"
  RELEASE_TAG="local:${ASSET_NAME}"
  log "repo=local release=${RELEASE_TAG} asset=${ASSET_NAME}"
  log "prefix=${PREFIX}"
  log "bin-dir=${BIN_DIR}"
  log "using local asset ${LOCAL_ASSET}"
else
  resolve_release
  log "repo=${REPO} release=${RELEASE_TAG} asset=${ASSET_NAME}"
  log "prefix=${PREFIX}"
  log "bin-dir=${BIN_DIR}"
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
fi

STAGE="${WORK}/stage"
mkdir -p "${STAGE}"
if [[ "${ASSET_NAME}" == *.portable.tar.gz ]]; then
  tar -xzf "${ASSET_PATH}" -C "${STAGE}"
  APPDIR="$(find "${STAGE}" -maxdepth 1 -type d \( -name 'StrawNT-*-x86_64.AppDir' -o -name 'StrawWU-Core-*-x86_64.AppDir' \) | head -n1 || true)"
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

CLI_SRC=""
for cand in strawnt strawwu; do
  if [[ -x "${SRC_ROOT}/bin/${cand}" ]]; then
    CLI_SRC="${cand}"
    break
  fi
done
[[ -n "${CLI_SRC}" ]] || die "missing bin/strawnt (or legacy bin/strawwu) in artifact"

log "installing into ${PREFIX}"
mkdir -p "${PREFIX}"
# Replace previous install contents but keep the prefix directory itself.
find "${PREFIX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "${SRC_ROOT}/." "${PREFIX}/"

# Ensure primary CLI is named strawnt.
if [[ ! -x "${PREFIX}/bin/strawnt" && -x "${PREFIX}/bin/strawwu" ]]; then
  cp -a "${PREFIX}/bin/strawwu" "${PREFIX}/bin/strawnt"
fi
chmod 755 "${PREFIX}/bin/strawnt" 2>/dev/null || true
[[ -x "${PREFIX}/bin/strawnt-env" ]] && chmod 755 "${PREFIX}/bin/strawnt-env" || true
[[ -x "${PREFIX}/bin/strawwu-env" ]] && chmod 755 "${PREFIX}/bin/strawwu-env" || true

# Wrapper so STRAWNT_PREFIX points at the installed tree.
WRAPPER="${PREFIX}/bin/strawnt-portable"
cat > "${WRAPPER}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export STRAWNT_PREFIX="${PREFIX}"
export STRAWWU_PREFIX="\${STRAWWU_PREFIX:-\${STRAWNT_PREFIX}}"
export STRAWNT_APP_REGISTRY="\${STRAWNT_APP_REGISTRY:-\${STRAWWU_APP_REGISTRY:-\${STRAWNT_PREFIX}/var/lib/strawnt/app-registry.json}}"
export STRAWWU_APP_REGISTRY="\${STRAWWU_APP_REGISTRY:-\${STRAWNT_APP_REGISTRY}}"
export STRAWNT_BACKEND="\${STRAWNT_BACKEND:-\${STRAWWU_BACKEND:-native}}"
export STRAWWU_BACKEND="\${STRAWWU_BACKEND:-\${STRAWNT_BACKEND}}"
export PATH="\${STRAWNT_PREFIX}/bin:\${PATH}"
export LD_LIBRARY_PATH="\${STRAWNT_PREFIX}/lib/strawnt:\${STRAWNT_PREFIX}/lib/strawwu:\${STRAWNT_PREFIX}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "\${STRAWNT_PREFIX}/bin/strawnt" "\$@"
EOF
chmod 755 "${WRAPPER}"

mkdir -p "${BIN_DIR}"
ln -sfn "${WRAPPER}" "${BIN_DIR}/strawnt"
# Compat alias (deprecated) — main path is strawnt.
ln -sfn "${WRAPPER}" "${BIN_DIR}/strawwu"

# Ensure BIN_DIR is on PATH for this shell and future login shells.
ensure_bin_on_path() {
  case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) export PATH="${BIN_DIR}:${PATH}" ;;
  esac
  local marker="# StrawNT PATH"
  for rc in "${HOME}/.profile" "${HOME}/.bashrc"; do
    [[ -f "${rc}" ]] || continue
    if ! grep -qF "${marker}" "${rc}" 2>/dev/null; then
      if ! grep -qF "${BIN_DIR}" "${rc}" 2>/dev/null; then
        printf '\n%s\n%s\n' "${marker}" "export PATH=\"${BIN_DIR}:\$PATH\"" >> "${rc}"
        log "added ${BIN_DIR} to PATH via ${rc}"
      fi
    fi
  done
  # Always create a sourceable env snippet.
  mkdir -p "${HOME}/.config/strawnt"
  cat > "${HOME}/.config/strawnt/env.sh" <<EOF
# Sourced by install / docs — puts StrawNT CLI on PATH.
export PATH="${BIN_DIR}:\$PATH"
export STRAWNT_PREFIX="${PREFIX}"
EOF
}
ensure_bin_on_path

# Pre-clear legacy StrawWU / temp-path open handlers that steal MIME defaults.
APPS_DIR="${HOME}/.local/share/applications"
MIME_DIR="${HOME}/.local/share/mime/packages"
mkdir -p "${APPS_DIR}" "${MIME_DIR}"
for stale in strawwu-open.desktop strawwu.desktop; do
  if [[ -f "${APPS_DIR}/${stale}" ]]; then
    rm -f "${APPS_DIR}/${stale}"
    log "removed stale desktop handler: ${APPS_DIR}/${stale}"
  fi
done
# Broken TryExec pointing at deleted /tmp/... leftovers.
if [[ -d "${APPS_DIR}" ]]; then
  while IFS= read -r -d '' desk; do
    try="$(awk -F= '/^TryExec=/{print $2; exit}' "${desk}" 2>/dev/null || true)"
    if [[ -n "${try}" && "${try}" == /* && ! -e "${try}" ]]; then
      base="$(basename "${desk}")"
      case "${base}" in
        strawwu*|strawnt-open.desktop|*.desktop)
          if grep -qiE 'strawwu|X-StrawWU|open %f|x-ms-dos-executable|x-msi' "${desk}"; then
            rm -f "${desk}"
            log "removed broken TryExec handler: ${desk} (was ${try})"
          fi
          ;;
      esac
    fi
  done < <(find "${APPS_DIR}" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null || true)
fi
rm -f "${MIME_DIR}/strawwu-win32.xml" 2>/dev/null || true

# Click-to-open: MIME handler so double-clicking .exe/.msi installs & launches.
export PATH="${BIN_DIR}:${PATH}"
export STRAWNT_PREFIX="${PREFIX}"
export STRAWWU_PREFIX="${PREFIX}"
export STRAWNT_BIN="${BIN_DIR}/strawnt"
export STRAWWU_BIN="${BIN_DIR}/strawnt"
mkdir -p "${PREFIX}/var/lib/strawnt" "${PREFIX}/var/lib/strawwu"
if [[ ! -f "${PREFIX}/var/lib/strawnt/app-registry.json" ]]; then
  if [[ -f "${PREFIX}/var/lib/strawwu/app-registry.json" ]]; then
    cp -a "${PREFIX}/var/lib/strawwu/app-registry.json" "${PREFIX}/var/lib/strawnt/app-registry.json"
  else
    printf '%s\n' '{"schema_version":"1.0","apps":[]}' > "${PREFIX}/var/lib/strawnt/app-registry.json"
  fi
fi
export STRAWNT_APP_REGISTRY="${STRAWNT_APP_REGISTRY:-${PREFIX}/var/lib/strawnt/app-registry.json}"
export STRAWWU_APP_REGISTRY="${STRAWWU_APP_REGISTRY:-${STRAWNT_APP_REGISTRY}}"
INTEGRATE_RC=0
if "${BIN_DIR}/strawnt" integrate; then
  log "desktop click-to-open enabled (.exe / .msi → native PE)"
else
  INTEGRATE_RC=$?
  log "WARNING: strawnt integrate failed (exit ${INTEGRATE_RC}) — run: strawnt integrate"
fi

# Smoke
VER_OUT="$("${BIN_DIR}/strawnt" --version 2>&1 || true)"
[[ -n "${VER_OUT}" ]] || die "post-install --version failed"
STATUS_OUT="$("${BIN_DIR}/strawnt" status 2>&1 || true)"
STATUS_RC=0
"${BIN_DIR}/strawnt" status >/dev/null 2>&1 || STATUS_RC=$?

cat <<EOF

StrawNT installed.

  release : ${RELEASE_TAG}
  prefix  : ${PREFIX}
  command : ${BIN_DIR}/strawnt
  version : ${VER_OUT}
  status  : exit ${STATUS_RC}
  click   : integrate exit ${INTEGRATE_RC}
  backend : native (StrawNT PE)

${STATUS_OUT}

Try:
  strawnt --version
  strawnt status
  strawnt open setup.exe     # wine/proton-ge path + app-menu shortcut
  # Or double-click any .exe / .msi in your file manager
  # App menu: StrawNT (runs status); MIME handler is hidden (NoDisplay)

If 'strawnt' is not found, add to PATH (or open a new login shell):
  export PATH="${BIN_DIR}:\$PATH"
  # or: source ~/.config/strawnt/env.sh

Note: .exe/.msi execution uses Wine/Proton-GE (execution_backend=wine; powered by Wine).
Not every Windows app will run; anti-cheat / kernel drivers may still fail.
Do not claim ranked / official anti-cheat pass. See docs/legal/WINE-LGPL.md.
StrawNT is an independent product — not an OS / ISO / desktop distribution.
EOF

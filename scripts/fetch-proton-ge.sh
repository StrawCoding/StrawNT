#!/usr/bin/env bash
# fetch-proton-ge.sh — download/verify/extract pinned Proton-GE into third_party/proton-ge/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GE_ROOT="${REPO_ROOT}/third_party/proton-ge"
PIN_FILE="${GE_ROOT}/PIN"
CACHE_DIR="${GE_ROOT}/cache"
DIST_DIR="${GE_ROOT}/dist"
WORKDIR="${STRAWNT_PROTON_GE_CACHE:-${REPO_ROOT}/.cache/proton-ge}"

die() { echo "fetch-proton-ge: ERROR: $*" >&2; exit 1; }

load_pin() {
  local pin_file="$1"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    if [[ "${line}" =~ ^([a-z_][a-z0-9_]*)=(.*)$ ]]; then
      printf -v "${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
    fi
  done < "${pin_file}"
}

[[ -f "${PIN_FILE}" ]] || die "missing ${PIN_FILE}"
[[ -s "${PIN_FILE}" ]] || die "empty ${PIN_FILE}"

load_pin "${PIN_FILE}"

[[ -n "${tag:-}" ]] || die "PIN missing tag="
[[ -n "${tarball_url:-}" ]] || die "PIN missing tarball_url="
[[ -n "${tarball_name:-}" ]] || die "PIN missing tarball_name="
[[ -n "${sha512:-}" ]] || die "PIN missing sha512="

mkdir -p "${CACHE_DIR}" "${DIST_DIR}" "${WORKDIR}"

TAR_CACHE="${CACHE_DIR}/${tarball_name}"
TAR_WORK="${WORKDIR}/${tarball_name}"
SUM_FILE="${CACHE_DIR}/${tag}.sha512sum"

need_download=0
if [[ ! -f "${TAR_CACHE}" ]]; then
  need_download=1
elif ! echo "${sha512}  ${TAR_CACHE}" | sha512sum -c - >/dev/null 2>&1; then
  echo "fetch-proton-ge: cache checksum mismatch; re-downloading"
  need_download=1
fi

if [[ "${need_download}" -eq 1 ]]; then
  echo "fetch-proton-ge: downloading ${tag} → ${TAR_WORK}"
  curl -fL --retry 3 --retry-delay 5 -o "${TAR_WORK}.partial" "${tarball_url}"
  mv -f "${TAR_WORK}.partial" "${TAR_WORK}"
  echo "${sha512}  ${TAR_WORK}" | sha512sum -c - || die "downloaded tarball sha512 mismatch"
  cp -f "${TAR_WORK}" "${TAR_CACHE}"
else
  echo "fetch-proton-ge: using cached ${TAR_CACHE}"
  echo "${sha512}  ${TAR_CACHE}" | sha512sum -c - || die "cache sha512 mismatch"
fi

if [[ -n "${sha512sum_url:-}" ]]; then
  curl -fsSL -o "${SUM_FILE}" "${sha512sum_url}" || true
fi

echo "fetch-proton-ge: extracting → ${DIST_DIR}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
tar -xzf "${TAR_CACHE}" -C "${DIST_DIR}" --strip-components=1

WINE_REL="${dist_wine_relpath:-files/bin/wine}"
WINE_BIN="${DIST_DIR}/${WINE_REL}"
[[ -x "${WINE_BIN}" ]] || die "missing wine binary after extract: ${WINE_BIN}"

# Record extract marker for doctor/status
{
  echo "tag=${tag}"
  echo "sha512=${sha512}"
  echo "extracted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "wine_bin=${WINE_REL}"
} > "${DIST_DIR}/.strawnt-engine-extract"

echo "fetch-proton-ge: OK pin=${tag} wine=${WINE_BIN}"

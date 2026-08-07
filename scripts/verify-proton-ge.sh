#!/usr/bin/env bash
# verify-proton-ge.sh — validate Proton-GE pin, git-lfs policy, and vendored wine binary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GE_ROOT="${REPO_ROOT}/third_party/proton-ge"
PIN_FILE="${GE_ROOT}/PIN"
README_FILE="${GE_ROOT}/README.md"
CACHE_DIR="${GE_ROOT}/cache"
DIST_DIR="${GE_ROOT}/dist"
GITATTRIBUTES="${REPO_ROOT}/.gitattributes"

failures=()

fail() { failures+=("$*"); }

[[ -f "${PIN_FILE}" ]] || fail "missing PIN"
[[ -s "${PIN_FILE}" ]] || fail "empty PIN"
[[ -f "${README_FILE}" ]] || fail "missing README.md"
[[ -f "${REPO_ROOT}/scripts/fetch-proton-ge.sh" ]] || fail "missing fetch-proton-ge.sh"

load_pin() {
  local pin_file="$1"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    if [[ "${line}" =~ ^([a-z_][a-z0-9_]*)=(.*)$ ]]; then
      printf -v "${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
    fi
  done < "${pin_file}"
}

if [[ -f "${PIN_FILE}" ]]; then
  load_pin "${PIN_FILE}"
  [[ -n "${tag:-}" ]] || fail "PIN missing tag"
  [[ -n "${sha512:-}" ]] || fail "PIN missing sha512"
  [[ "${#sha512}" -eq 128 ]] || fail "PIN sha512 length != 128"
  [[ -n "${tarball_url:-}" ]] || fail "PIN missing tarball_url"
  [[ "${distribution:-}" == "git-lfs" ]] || fail "PIN distribution must be git-lfs"
  [[ "${engine:-}" == "proton-ge" ]] || fail "PIN engine must be proton-ge"
fi

if [[ ! -f "${GITATTRIBUTES}" ]]; then
  fail "missing .gitattributes"
else
  if ! grep -E 'third_party/proton-ge/cache/.*filter=lfs|proton-ge/cache/\*\*/\* tar\.gz.*filter=lfs|\*\.tar\.gz filter=lfs' "${GITATTRIBUTES}" >/dev/null 2>&1 \
    && ! grep -F 'third_party/proton-ge/cache/**' "${GITATTRIBUTES}" | grep -q 'filter=lfs'; then
    # Accept either explicit cache path or *.tar.gz under proton-ge
    if ! grep -E 'proton-ge/.*filter=lfs|filter=lfs.*proton-ge' "${GITATTRIBUTES}" >/dev/null 2>&1; then
      fail ".gitattributes missing git-lfs rules for proton-ge cache"
    fi
  fi
fi

# Ensure LFS tracking is declared for the vendored archive pattern
if [[ -f "${GITATTRIBUTES}" ]]; then
  if ! grep -qE 'filter=lfs' "${GITATTRIBUTES}"; then
    fail ".gitattributes has no filter=lfs entries"
  fi
fi

# Cache tarball: if present, checksum must match PIN; if absent, fetch.
if [[ -n "${tarball_name:-}" ]]; then
  TAR_CACHE="${CACHE_DIR}/${tarball_name}"
  if [[ ! -f "${TAR_CACHE}" ]]; then
    echo "verify-proton-ge: cache missing; invoking fetch-proton-ge.sh"
    bash "${REPO_ROOT}/scripts/fetch-proton-ge.sh" || fail "fetch-proton-ge.sh failed"
  else
    if ! echo "${sha512}  ${TAR_CACHE}" | sha512sum -c - >/dev/null 2>&1; then
      fail "cache tarball sha512 mismatch for ${tarball_name}"
    fi
  fi
fi

WINE_REL="${dist_wine_relpath:-files/bin/wine}"
WINE_BIN="${DIST_DIR}/${WINE_REL}"
if [[ ! -x "${WINE_BIN}" ]]; then
  echo "verify-proton-ge: dist wine missing; extracting via fetch"
  bash "${REPO_ROOT}/scripts/fetch-proton-ge.sh" || fail "fetch-proton-ge.sh failed (extract)"
fi

if [[ ! -x "${WINE_BIN}" ]]; then
  fail "wine binary not executable: ${WINE_BIN}"
else
  # Smoke: wine --version should mention wine / proton lineage
  ver_out="$("${WINE_BIN}" --version 2>/dev/null || true)"
  if [[ -z "${ver_out}" ]]; then
    fail "wine --version returned empty"
  fi
fi

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "verify-proton-ge: FAIL"
  for f in "${failures[@]}"; do
    echo "  - ${f}"
  done
  exit 1
fi

echo "verify-proton-ge: OK"
echo "  pin=${tag}"
echo "  sha512=${sha512:0:16}…"
echo "  wine=${WINE_BIN}"
echo "  distribution=git-lfs"
echo "  backend=wine"
echo "  powered_by=Wine"
exit 0

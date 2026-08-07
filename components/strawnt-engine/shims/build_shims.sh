#!/usr/bin/env bash
# Build StrawWine wintrust soft-pass shims (x86_64 + i686).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$(cd "${ROOT}/../data/shims" && pwd)}"
mkdir -p "${OUT}"

build_one() {
  local cc="$1" arch="$2"
  command -v "${cc}" >/dev/null || { echo "skip ${arch}: ${cc} missing" >&2; return 0; }
  "${cc}" -shared -O2 -s \
    -o "${OUT}/wintrust_${arch}.dll" \
    "${ROOT}/wintrust_shim.c" \
    "${ROOT}/wintrust_shim.def"
  # Install name expected in Wine system32 / syswow64
  cp -f "${OUT}/wintrust_${arch}.dll" "${OUT}/wintrust.dll.${arch}"
  echo "built ${OUT}/wintrust_${arch}.dll"
}

build_one x86_64-w64-mingw32-gcc x86_64
build_one i686-w64-mingw32-gcc i686
ls -la "${OUT}"

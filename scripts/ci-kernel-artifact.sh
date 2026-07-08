#!/usr/bin/env bash
# ci-kernel-artifact.sh — Q6: SHA256SUMS + kernel-manifest.json for linux-image-strawwu .deb.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${STRAWWU_KERNEL_OUTPUT_DIR:-${REPO_ROOT}/kernel/output}"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
MANIFEST_PATH="${OUTPUT_DIR}/kernel-manifest.json"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--check]

Generate SHA256SUMS and kernel-manifest.json for linux-image-strawwu .deb artifacts.

Environment:
  STRAWWU_KERNEL_OUTPUT_DIR   Kernel output directory (default: kernel/output)
  STRAWWU_VERSION             Product version from VERSION file
EOF
}

check_only=false
if [[ "${1:-}" == "--check" ]]; then
    check_only=true
fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

find_kernel_deb() {
    find "${OUTPUT_DIR}" -maxdepth 1 -name 'linux-image-strawwu_*.deb' 2>/dev/null | head -1
}

git_sha() {
    if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "${REPO_ROOT}" rev-parse HEAD
    else
        echo "unknown"
    fi
}

if [[ "${check_only}" == true ]]; then
    [[ -f "${REPO_ROOT}/kernel/Makefile" ]] || die "missing kernel/Makefile"
    [[ -f "${REPO_ROOT}/kernel/build.sh" ]] || die "missing kernel/build.sh"
    log "ci-kernel-artifact.sh --check OK"
    exit 0
fi

mkdir -p "${OUTPUT_DIR}"
deb="$(find_kernel_deb)"
[[ -n "${deb}" ]] || die "no linux-image-strawwu_*.deb in ${OUTPUT_DIR}"
[[ -f "${OUTPUT_DIR}/.build-ok" ]] || die "missing kernel build marker ${OUTPUT_DIR}/.build-ok"

deb_name="$(basename "${deb}")"
(
    cd "${OUTPUT_DIR}"
    sha256sum "${deb_name}" > SHA256SUMS
)
log "SHA256SUMS written for ${deb_name}"

python3 - "${MANIFEST_PATH}" "${VERSION}" "${deb}" "${OUTPUT_DIR}" "${REPO_ROOT}" "$(git_sha)" <<'PY'
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

manifest_path, version, deb_path, output_dir, repo, git_sha = sys.argv[1:7]
deb = Path(deb_path)
output = Path(output_dir)

sha256 = hashlib.sha256(deb.read_bytes()).hexdigest()
abi_match = re.search(r"linux-image-strawwu_([^_]+)_", deb.name)
kernel_abi = abi_match.group(1) if abi_match else "unknown"

manifest = {
    "schema": "strawwu-kernel-manifest/v1",
    "product_version": version,
    "kernel_abi": kernel_abi,
    "channel": "kernel-ci",
    "published_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "git_sha": git_sha,
    "artifacts": [
        {
            "name": deb.name,
            "type": "linux-image-strawwu",
            "sha256": sha256,
            "size_bytes": deb.stat().st_size,
        }
    ],
    "build": {
        "runner": "self-hosted",
        "workflow": ".github/workflows/kernel-build.yml",
        "make_target": "kernel-build",
    },
}
Path(manifest_path).write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
print(f"kernel-manifest.json: {deb.name} abi={kernel_abi}")
PY

log "kernel-manifest.json → ${MANIFEST_PATH}"

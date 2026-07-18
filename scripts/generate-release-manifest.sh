#!/usr/bin/env bash
# generate-release-manifest.sh — RE1: build release-manifest.json for StrawWU artifacts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${STRAWWU_OUTPUT_DIR:-${REPO_ROOT}/os-image/output}"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
CHANNEL="${STRAWWU_RELEASE_CHANNEL:-}"
MANIFEST_PATH="${OUTPUT_DIR}/release-manifest.json"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

parse_channel() {
    if [[ -n "${CHANNEL}" ]]; then
        echo "${CHANNEL}"
        return
    fi
    local preview
    preview="$(echo "${VERSION}" | awk -F. '{print $4}')"
    if [[ "${preview:-0}" -gt 0 ]] 2>/dev/null; then
        echo "beta"
    else
        echo "stable"
    fi
}

git_field() {
    local field="$1"
    if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        case "${field}" in
            sha) git -C "${REPO_ROOT}" rev-parse HEAD ;;
            tag)
                local tag
                tag="$(git -C "${REPO_ROOT}" tag -l "v${VERSION}" 2>/dev/null | head -1 || true)"
                if [[ -n "${tag}" ]]; then
                    echo "${tag}"
                else
                    echo "null"
                fi
                ;;
        esac
    else
        [[ "${field}" == "tag" ]] && echo "null" || echo "unknown"
    fi
}

artifact_gpg_sig() {
    local name="$1"
    local asc="${OUTPUT_DIR}/${name}.asc"
    if [[ -f "${asc}" ]]; then
        printf '%s' "${asc#${OUTPUT_DIR}/}"
    else
        echo "null"
    fi
}

main() {
    mkdir -p "${OUTPUT_DIR}"

    local channel git_sha git_tag published_at iso_name iso_path
    channel="$(parse_channel)"
    git_sha="$(git_field sha)"
    git_tag="$(git_field tag)"
    published_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    iso_name="StrawWU-${VERSION}-amd64.iso"
    iso_path="${OUTPUT_DIR}/${iso_name}"

    python3 - "${MANIFEST_PATH}" "${VERSION}" "${channel}" "${git_sha}" "${git_tag}" \
        "${published_at}" "${iso_path}" "${OUTPUT_DIR}" "${REPO_ROOT}" <<'PY'
import hashlib
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

manifest_path, version, channel, git_sha, git_tag, published_at, iso_path, output_dir, repo = sys.argv[1:10]
output = Path(output_dir)
repo_root = Path(repo)
iso = Path(iso_path)
include_all = os.environ.get("STRAWWU_MANIFEST_ALL_ISOS", "0") == "1"

def read_checksums() -> dict[str, str]:
    sums_path = output / "SHA256SUMS"
    if not sums_path.is_file():
        return {}
    mapping = {}
    for line in sums_path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            mapping[parts[-1]] = parts[0]
    return mapping

checksum_index = read_checksums()

def artifact_entry(candidate: Path) -> dict:
    asc = output / f"{candidate.name}.asc"
    digest = checksum_index.get(candidate.name)
    if not digest:
        digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
    return {
        "name": candidate.name,
        "sha256": digest,
        "size": candidate.stat().st_size,
        "gpg_sig": candidate.name + ".asc" if asc.is_file() else None,
    }

artifacts = []
if iso.is_file():
    artifacts.append(artifact_entry(iso))
elif include_all:
    for candidate in sorted(output.glob("StrawWU-*.iso")):
        artifacts.append(artifact_entry(candidate))
else:
    candidates = sorted(output.glob("StrawWU-*.iso"), key=lambda p: p.stat().st_mtime)
    if candidates:
        artifacts.append(artifact_entry(candidates[-1]))

packages = []
deb_dirs = sorted((repo_root / "os-image/debs").glob("*/debian/control"))
for control in deb_dirs:
    text = control.read_text(encoding="utf-8", errors="replace")
    pkg_match = re.search(r"^Package:\s*(\S+)", text, re.M)
    ver_match = re.search(r"^Version:\s*(\S+)", text, re.M)
    if pkg_match:
        pkg_ver = ver_match.group(1) if ver_match else version
        if pkg_ver == "__VERSION__":
            pkg_ver = version
        packages.append({"name": pkg_match.group(1), "version": pkg_ver})

for deb in sorted((repo_root / "packaging/output").glob("*.deb")):
    m = re.match(r"^(.+?)_([^_]+)_(all|amd64)\.deb$", deb.name)
    if m:
        packages.append({"name": m.group(1), "version": m.group(2)})

# de-duplicate packages by name (prefer packaging/output version)
seen = {}
for pkg in packages:
    seen[pkg["name"]] = pkg["version"]
packages = [{"name": k, "version": v} for k, v in sorted(seen.items())]

boot_test = {"bios": "PENDING", "uefi": "PENDING", "secureboot": "PENDING"}
boot_result = repo_root / "tests/boot/output/boot-result.json"
if boot_result.is_file():
    try:
        result = json.loads(boot_result.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        result = {}
    if result.get("version") == version:
        for mode in boot_test:
            status = (result.get(mode) or {}).get("status")
            if status in {"PASS", "FAIL", "SKIPPED"}:
                boot_test[mode] = status

sha256sums = output / "SHA256SUMS"
checksums = None
if sha256sums.is_file():
    checksums = {
        "file": "SHA256SUMS",
        "gpg_sig": "SHA256SUMS.asc" if (output / "SHA256SUMS.asc").is_file() else None,
    }

data = {
    "schema": "strawwu-release-manifest/v1",
    "version": version,
    "channel": channel,
    "git_tag": None if git_tag == "null" else git_tag,
    "git_sha": git_sha,
    "artifacts": artifacts,
    "packages": packages,
    "boot_test": boot_test,
    "checksums": checksums,
    "published_at": published_at,
}

Path(manifest_path).write_text(
    json.dumps(data, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
print(json.dumps({"manifest": manifest_path, "artifacts": len(artifacts), "packages": len(packages)}))
PY

    log "release manifest written ${MANIFEST_PATH}"
}

main "$@"

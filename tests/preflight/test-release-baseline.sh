#!/usr/bin/env bash
# RE0: Release engineering baseline + release-baseline.json.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== RE0 release-baseline preflight ==="

require_plan "strawwu-release-engineering-plan.md"
require_file "${REPO_ROOT}/docs/versioning.md" "docs/versioning.md"
require_file "${REPO_ROOT}/docs/iso-modes.md" "docs/iso-modes.md"
require_file "${REPO_ROOT}/VERSION" "VERSION file"
require_file "${REPO_ROOT}/os-image/scripts/build-iso.sh" "build-iso.sh"
require_file "${REPO_ROOT}/scripts/bump-version.sh" "bump-version.sh"

ubuntu_list_file="$(mktemp)"
iso_list_file="$(mktemp)"
trap 'rm -f "${ubuntu_list_file}" "${iso_list_file}"' EXIT

if has_squashfs; then
    list_squashfs_packages | grep -E '^ubuntu-' > "${ubuntu_list_file}" || true
    pass "squashfs ubuntu-* package scan count=$(wc -l < "${ubuntu_list_file}")"
else
    : > "${ubuntu_list_file}"
    warn "squashfs missing — ubuntu package list empty"
fi

if [[ -d "${REPO_ROOT}/os-image/output" ]]; then
    find "${REPO_ROOT}/os-image/output" -maxdepth 1 -name 'StrawWU-*.iso' -printf '%f\n' 2>/dev/null | sort > "${iso_list_file}" || true
else
    : > "${iso_list_file}"
fi

gpg_ready=false
if command -v gpg >/dev/null 2>&1 && gpg --list-secret-keys 2>/dev/null | grep -qi strawwu; then
    gpg_ready=true
fi

python3 - "${BASELINES_DIR}/release-baseline.json" "${VERSION}" "${REPO_ROOT}" "${ubuntu_list_file}" "${iso_list_file}" "${gpg_ready}" <<'PY'
import json, sys
from pathlib import Path

out, version, repo, ubuntu_file, iso_file, gpg_ready = sys.argv[1:7]
ubuntu = Path(ubuntu_file).read_text().splitlines()
ubuntu = [x for x in ubuntu if x.strip()]
isos = Path(iso_file).read_text().splitlines()
isos = [x for x in isos if x.strip()]
repo_path = Path(repo)
squashfs_status = repo_path / "os-image/work/squashfs-root/var/lib/dpkg/status"

data = {
    "schema": "strawwu-release-baseline/v1",
    "generated_at": "2026-07-04",
    "version": version,
    "channels": {
        "dev": {"iso_mode": "dev-iso", "compression": "zstd", "signed": False},
        "nightly": {"iso_mode": "dev-iso", "compression": "zstd", "signed": False},
        "beta": {"iso_mode": "release-iso", "compression": "xz", "signed": "sha256+gpg"},
        "stable": {"iso_mode": "release-iso", "compression": "xz", "signed": "sha256+gpg"},
    },
    "squashfs": {
        "present": squashfs_status.is_file(),
        "ubuntu_packages": ubuntu,
        "ubuntu_package_count": len(ubuntu),
        "strawwu_deb_count": 0,
    },
    "artifacts": {
        "iso_files": isos,
        "latest_iso": isos[-1] if isos else None,
        "gpg_signing_ready": gpg_ready.lower() == "true",
        "apt_repo_ready": False,
        "release_manifest_ready": False,
    },
    "scripts": {
        "build_iso": "os-image/scripts/build-iso.sh",
        "bump_version": "scripts/bump-version.sh",
        "release_sign": None,
        "publish_debs": None,
    },
    "wave0_gaps": [
        "no GPG release-sign script",
        "no APT publish pipeline",
        "no release-manifest.json generator",
        f"{len(ubuntu)} ubuntu-* packages still in squashfs",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

pass "baseline written ${BASELINES_DIR}/release-baseline.json"
validate_json_file "${BASELINES_DIR}/release-baseline.json"

preflight_exit "RE0 release-baseline"

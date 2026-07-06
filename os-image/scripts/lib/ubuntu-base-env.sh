#!/usr/bin/env bash
# Load Ubuntu base version/codename from docs/plans/ubuntu-base-target.json (active slot).
# Override with STRAWWU_UBUNTU_VERSION / STRAWWU_APT_SUITE / STRAWWU_UBUNTU_MIRROR.
set -euo pipefail

load_ubuntu_base_env() {
    local repo_root="${1:?repo root required}"
    local target_json="${repo_root}/docs/plans/ubuntu-base-target.json"
    local default_version="24.04.2"
    local default_codename="noble"
    local default_mirror="https://old-releases.ubuntu.com/releases/${default_version}"

    if [[ -f "${target_json}" ]] && command -v python3 >/dev/null 2>&1; then
        eval "$(python3 - "${target_json}" <<'PY'
import json, pathlib, sys
t = json.loads(pathlib.Path(sys.argv[1]).read_text())
a = t.get("active", {})
v = a.get("version", "24.04.2")
iso = a.get("iso_name") or f"ubuntu-{v}-desktop-amd64.iso"
mirror = a.get("mirror") or f"https://releases.ubuntu.com/{v}"
codename = a.get("codename", "noble")
print(f"export _UBUNTU_BASE_VERSION='{v}'")
print(f"export _UBUNTU_BASE_ISO='{iso}'")
print(f"export _UBUNTU_BASE_MIRROR='{mirror}'")
print(f"export _UBUNTU_BASE_CODENAME='{codename}'")
PY
)"
        default_version="${_UBUNTU_BASE_VERSION}"
        default_codename="${_UBUNTU_BASE_CODENAME}"
        default_mirror="${_UBUNTU_BASE_MIRROR}"
        export _UBUNTU_BASE_ISO_NAME="${_UBUNTU_BASE_ISO}"
    else
        export _UBUNTU_BASE_ISO_NAME="ubuntu-${default_version}-desktop-amd64.iso"
    fi

    export STRAWWU_UBUNTU_VERSION="${STRAWWU_UBUNTU_VERSION:-${default_version}}"
    export STRAWWU_APT_SUITE="${STRAWWU_APT_SUITE:-${default_codename}}"
    export STRAWWU_UBUNTU_MIRROR="${STRAWWU_UBUNTU_MIRROR:-${default_mirror}}"
    export STRAWWU_UBUNTU_ISO_NAME="${STRAWWU_UBUNTU_ISO_NAME:-${_UBUNTU_BASE_ISO_NAME:-ubuntu-${STRAWWU_UBUNTU_VERSION}-desktop-amd64.iso}}"
}

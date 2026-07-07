#!/usr/bin/env bash
# fork-apt-env.sh — Resolve strawwu-fork APT suite paths from packages.json + ubuntu-base-target.json.
set -euo pipefail

load_fork_apt_env() {
    local repo_root="${1:?repo root required}"
    local target_json="${repo_root}/docs/plans/ubuntu-base-target.json"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # shellcheck source=os-image/scripts/lib/fork-packages-env.sh
    source "${script_dir}/fork-packages-env.sh"
    load_fork_packages_env "${repo_root}"

    local default_suite="strawwu-fork"
    local default_sources="os-image/config/branding/etc/apt/sources.list.d/strawwu-fork.sources"
    local default_repo_dir="os-image/output/apt-fork-repo"

    if [[ -f "${STRAWWU_FORK_PACKAGES_REGISTRY}" ]] && command -v python3 >/dev/null 2>&1; then
        eval "$(python3 - "${STRAWWU_FORK_PACKAGES_REGISTRY}" <<'PY'
import json, pathlib, sys
registry = json.loads(pathlib.Path(sys.argv[1]).read_text())
suite = registry.get("publish_suite", "strawwu-fork")
print(f"export _FORK_APT_SUITE='{suite}'")
PY
)"
        default_suite="${_FORK_APT_SUITE}"
    fi

    if [[ -f "${target_json}" ]] && command -v python3 >/dev/null 2>&1; then
        eval "$(python3 - "${target_json}" <<'PY'
import json, pathlib, sys
fork = (json.loads(pathlib.Path(sys.argv[1]).read_text()).get("fork") or {})
suite = fork.get("apt_fork_suite", "strawwu-fork")
sources = fork.get("apt_fork_sources", "os-image/config/branding/etc/apt/sources.list.d/strawwu-fork.sources")
repo = fork.get("apt_fork_repo_dir", "os-image/output/apt-fork-repo")
print(f"export _FORK_APT_SUITE='{suite}'")
print(f"export _FORK_APT_SOURCES_REL='{sources}'")
print(f"export _FORK_APT_REPO_REL='{repo}'")
PY
)"
        default_suite="${_FORK_APT_SUITE}"
        default_sources="${_FORK_APT_SOURCES_REL}"
        default_repo_dir="${_FORK_APT_REPO_REL}"
    fi

    export STRAWWU_FORK_APT_SUITE="${STRAWWU_FORK_APT_SUITE:-${default_suite}}"
    export STRAWWU_FORK_APT_SOURCES="${STRAWWU_FORK_APT_SOURCES:-${repo_root}/${default_sources}}"
    export STRAWWU_FORK_APT_REPO_DIR="${STRAWWU_FORK_APT_REPO_DIR:-${repo_root}/${default_repo_dir}}"
}

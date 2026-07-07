#!/usr/bin/env bash
# fork-packages-env.sh — Resolve fork package overlay paths from ubuntu-base-target.json.
set -euo pipefail

load_fork_packages_env() {
    local repo_root="${1:?repo root required}"
    local target_json="${repo_root}/docs/plans/ubuntu-base-target.json"
    local default_dir="os-image/fork/packages"

    if [[ -f "${target_json}" ]] && command -v python3 >/dev/null 2>&1; then
        eval "$(python3 - "${target_json}" <<'PY'
import json, pathlib, sys
t = json.loads(pathlib.Path(sys.argv[1]).read_text())
rel = (t.get("fork") or {}).get("fork_packages_dir", "os-image/fork/packages")
print(f"export _FORK_PACKAGES_REL='{rel}'")
PY
)"
        default_dir="${_FORK_PACKAGES_REL}"
    fi

    export STRAWWU_FORK_PACKAGES_DIR="${STRAWWU_FORK_PACKAGES_DIR:-${repo_root}/${default_dir}}"
    export STRAWWU_FORK_PACKAGES_REGISTRY="${STRAWWU_FORK_PACKAGES_REGISTRY:-${STRAWWU_FORK_PACKAGES_DIR}/packages.json}"
    export STRAWWU_FORK_PACKAGES_OUTPUT="${STRAWWU_FORK_PACKAGES_OUTPUT:-${STRAWWU_FORK_PACKAGES_DIR}/output}"
}

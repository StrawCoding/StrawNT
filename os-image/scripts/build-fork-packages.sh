#!/usr/bin/env bash
# build-fork-packages.sh — Build registered fork upstream package overlays.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=os-image/scripts/lib/fork-packages-env.sh
source "${SCRIPT_DIR}/lib/fork-packages-env.sh"

load_fork_packages_env "${REPO_ROOT}"

VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
REGISTRY="${STRAWWU_FORK_PACKAGES_REGISTRY}"
PACKAGES_ROOT="${STRAWWU_FORK_PACKAGES_DIR}"
OUTPUT_ROOT="${STRAWWU_FORK_PACKAGES_OUTPUT}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

validate_scaffold() {
    local scaffold="${PACKAGES_ROOT}/$(python3 - "${REGISTRY}" <<'PY'
import json, pathlib, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(r.get("scaffold_dir", "_template"))
PY
)"
    bash "${SCRIPT_DIR}/validate-fork-package.sh" "${scaffold}"
}

list_registered_packages() {
    python3 - "${REGISTRY}" <<'PY'
import json, pathlib, sys
registry = json.loads(pathlib.Path(sys.argv[1]).read_text())
for name in registry.get("packages") or []:
    print(name)
PY
}

build_one() {
    local name="$1"
    local pkg_dir="${PACKAGES_ROOT}/${name}"
    local build="${pkg_dir}/build-package.sh"
    [[ -d "${pkg_dir}" ]] || die "registered package missing directory: ${pkg_dir}"
    bash "${SCRIPT_DIR}/validate-fork-package.sh" "${pkg_dir}"
    [[ -x "${build}" ]] || die "missing build script: ${build}"
    log "building fork package ${name} v${VERSION}"
    STRAWWU_VERSION="${VERSION}" bash "${build}"
}

main() {
    [[ -f "${REGISTRY}" ]] || die "missing registry: ${REGISTRY}"
    mkdir -p "${OUTPUT_ROOT}"

    validate_scaffold

    mapfile -t packages < <(list_registered_packages)
    if [[ "${#packages[@]}" -eq 0 ]]; then
        log "no registered fork packages (scaffold validated only)"
        return 0
    fi

    for pkg in "${packages[@]}"; do
        build_one "${pkg}"
    done
    log "built ${#packages[@]} fork package(s) → ${OUTPUT_ROOT}"
}

main "$@"

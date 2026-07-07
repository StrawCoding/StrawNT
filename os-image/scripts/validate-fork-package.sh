#!/usr/bin/env bash
# validate-fork-package.sh — Static validation for one fork package overlay directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=os-image/scripts/lib/fork-packages-env.sh
source "${SCRIPT_DIR}/lib/fork-packages-env.sh"

load_fork_packages_env "${REPO_ROOT}"

PKG_DIR="${1:?package directory required}"
PKG_NAME="$(basename "${PKG_DIR}")"
REGISTRY="${STRAWWU_FORK_PACKAGES_REGISTRY}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "${PKG_DIR}" ]] || die "missing package directory: ${PKG_DIR}"
[[ -f "${REGISTRY}" ]] || die "missing registry: ${REGISTRY}"

python3 - "${REGISTRY}" "${PKG_DIR}" "${PKG_NAME}" <<'PY'
import json, pathlib, sys

registry_path = pathlib.Path(sys.argv[1])
pkg_dir = pathlib.Path(sys.argv[2])
pkg_name = sys.argv[3]

registry = json.loads(registry_path.read_text())
assert registry.get("schema") == "strawwu-fork-packages/v1", "packages.json schema"
layout = registry.get("directory_layout") or {}
required = layout.get("required") or ["PACKAGE.yaml", "debian/control", "build-package.sh"]

for rel in required:
    path = pkg_dir / rel
    assert path.is_file(), f"{pkg_name}: missing required file {rel}"

build = pkg_dir / "build-package.sh"
assert build.stat().st_mode & 0o111, f"{pkg_name}: build-package.sh not executable"

pkg_yaml = pkg_dir / "PACKAGE.yaml"
text = pkg_yaml.read_text()
assert "schema: strawwu-fork-package/v1" in text, f"{pkg_name}: PACKAGE.yaml schema"
assert "upstream:" in text and "fork:" in text, f"{pkg_name}: PACKAGE.yaml missing upstream/fork blocks"

if pkg_name == (registry.get("scaffold_dir") or "_template"):
    assert "status: template" in text, f"{pkg_name}: scaffold must keep status: template"
print(f"PASS: validate {pkg_name}")
PY

bash -n "${PKG_DIR}/build-package.sh"
log "validated ${PKG_NAME}"

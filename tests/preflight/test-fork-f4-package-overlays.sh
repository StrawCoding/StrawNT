#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

FORK_PKG="${REPO_ROOT}/os-image/fork/packages"
SCRIPTS="${REPO_ROOT}/os-image/scripts"

echo "=== FORK-F4 package-overlays gate ==="
require_file "${FORK_PKG}/README.md" "fork/packages README"
require_file "${FORK_PKG}/packages.json" "fork/packages registry"
require_file "${FORK_PKG}/.gitignore" "fork/packages gitignore"
require_file "${FORK_PKG}/_template/PACKAGE.yaml" "fork package scaffold PACKAGE.yaml"
require_file "${FORK_PKG}/_template/debian/control" "fork package scaffold debian/control"
require_file "${FORK_PKG}/_template/build-package.sh" "fork package scaffold build-package.sh"
require_file "${SCRIPTS}/build-fork-packages.sh" "build-fork-packages.sh"
require_file "${SCRIPTS}/validate-fork-package.sh" "validate-fork-package.sh"
require_file "${SCRIPTS}/lib/fork-packages-env.sh" "fork-packages-env.sh"

bash -n "${SCRIPTS}/build-fork-packages.sh"
pass "build-fork-packages.sh syntax"
bash -n "${SCRIPTS}/validate-fork-package.sh"
pass "validate-fork-package.sh syntax"
bash -n "${SCRIPTS}/lib/fork-packages-env.sh"
pass "fork-packages-env.sh syntax"

grep -q 'build-fork-packages' "${REPO_ROOT}/Makefile" && pass "Makefile build-fork-packages target"

grep -q 'fork_packages_dir' "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" \
    && pass "ubuntu-base-target fork_packages_dir"

bash "${SCRIPTS}/validate-fork-package.sh" "${FORK_PKG}/_template"
pass "scaffold validation"

bash "${SCRIPTS}/build-fork-packages.sh" >/tmp/fork-f4-build.log 2>&1 \
    && pass "build-fork-packages scaffold-only run"

python3 - "${FORK_PKG}/packages.json" "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" <<'PY'
import json, pathlib, sys

registry = json.loads(pathlib.Path(sys.argv[1]).read_text())
base = json.loads(pathlib.Path(sys.argv[2]).read_text())

assert registry.get("schema") == "strawwu-fork-packages/v1", "packages.json schema"
assert registry.get("publish_suite") == "strawwu-fork", "publish_suite"
assert registry.get("scaffold_dir") == "_template", "scaffold_dir"
assert isinstance(registry.get("packages"), list), "packages must be list"

fork_dir = base.get("fork", {}).get("fork_packages_dir")
assert fork_dir == "os-image/fork/packages", f"fork_packages_dir mismatch: {fork_dir}"
print("PASS: packages.json schema + ubuntu-base-target alignment")
PY

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F4 STATIC OK"

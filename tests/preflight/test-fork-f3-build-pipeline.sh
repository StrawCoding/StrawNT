#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== FORK-F3 build-pipeline gate ==="

require_file "${REPO_ROOT}/os-image/scripts/fork-sync-base.sh" "fork-sync-base.sh"
require_file "${REPO_ROOT}/os-image/scripts/sync-base.sh" "sync-base.sh"
require_file "${REPO_ROOT}/os-image/scripts/lib/base-marker.sh" "base-marker.sh"

bash -n "${REPO_ROOT}/os-image/scripts/fork-sync-base.sh"
bash -n "${REPO_ROOT}/os-image/scripts/sync-base.sh"
bash -n "${REPO_ROOT}/os-image/scripts/lib/base-marker.sh"

grep -q 'die_unless_base_marker\|fork-sync-base-ok' "${REPO_ROOT}/os-image/scripts/build-iso.sh" \
    && pass "build-iso accepts fork marker"
grep -q 'sync-base' "${REPO_ROOT}/Makefile" && pass "Makefile sync-base target"
grep -q 'fork-sync-base' "${REPO_ROOT}/Makefile" && pass "Makefile fork-sync-base target"
grep -q 'STRAWWU_BASE_MODE' "${REPO_ROOT}/os-image/scripts/lib/ubuntu-base-env.sh" \
    && pass "ubuntu-base-env exports STRAWWU_BASE_MODE"

for script in chroot-purge-ubuntu-telemetry.sh chroot-install-target-setup.sh swap-kernel.sh; do
    grep -q 'die_unless_base_marker' "${REPO_ROOT}/os-image/scripts/${script}" \
        && pass "${script} accepts fork marker"
done

python3 - "${REPO_ROOT}/os-image/scripts/lib/ubuntu-base-env.sh" "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" <<'PY'
import pathlib, subprocess, sys
env = subprocess.run(
    ["bash", "-c", f"source {sys.argv[1]} && load_ubuntu_base_env {pathlib.Path(sys.argv[2]).parent.parent.parent} && echo $STRAWWU_BASE_MODE"],
    capture_output=True, text=True, check=True,
)
mode = env.stdout.strip()
assert mode in ("clone", "fork"), f"unexpected STRAWWU_BASE_MODE={mode!r}"
print(f"PASS: STRAWWU_BASE_MODE resolves to {mode}")
PY

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F3 STATIC OK"

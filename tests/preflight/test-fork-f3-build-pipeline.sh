#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== FORK-F3 build-pipeline gate ==="
grep -q 'fork-sync-base-ok\|fork-sync-base' "${REPO_ROOT}/os-image/scripts/build-iso.sh" && pass "build-iso accepts fork marker"
grep -q fork-sync-base "${REPO_ROOT}/Makefile" && pass "Makefile fork-sync-base"
bash -n "${REPO_ROOT}/os-image/scripts/fork-sync-base.sh"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F3 STATIC OK"

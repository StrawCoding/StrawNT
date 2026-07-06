#!/usr/bin/env bash
# fork-f1 static gate: fork baseline snapshot infrastructure.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== FORK-F1 baseline-snapshot gate ==="
require_file "${REPO_ROOT}/os-image/scripts/fork-baseline-snapshot.sh" "fork-baseline-snapshot.sh"
require_file "${REPO_ROOT}/os-image/fork-base/manifest.json" "manifest.json"
bash -n "${REPO_ROOT}/os-image/scripts/fork-baseline-snapshot.sh"
grep -q fork-baseline-snapshot "${REPO_ROOT}/Makefile" && pass "Makefile fork-baseline-snapshot target"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F1 STATIC OK"

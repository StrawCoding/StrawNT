#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== FORK-F6 regression-e2e gate ==="
require_file "${REPO_ROOT}/tests/u26/write-regression-marker.sh" "u26 regression marker (reuse)"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F6 STATIC OK"

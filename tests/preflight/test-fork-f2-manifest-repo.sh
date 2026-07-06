#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== FORK-F2 manifest-repo gate ==="
for f in include.txt remove.txt replace.json pins.txt; do
    require_file "${REPO_ROOT}/os-image/fork-base/packages/${f}" "packages/${f}"
done
python3 -c "import json; json.load(open('${REPO_ROOT}/os-image/fork-base/packages/replace.json'))"
if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F2 STATIC OK"

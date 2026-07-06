#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== POST-UPG rollback preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
fail "strawwu-upgrade not implemented yet"
exit "${PREFLIGHT_FAIL}"

#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== POST-CI kernel selfhosted preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
fail "self-hosted kernel CI not implemented yet"
exit "${PREFLIGHT_FAIL}"

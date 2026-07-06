#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== POST-Q8 golden apps preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
bash "${REPO_ROOT}/tests/wincompat/test-golden-apps.sh"

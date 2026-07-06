#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== POST-Q3 MFP smoke preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
bash "${REPO_ROOT}/tests/device-proxy/test-mfp-smoke.sh"

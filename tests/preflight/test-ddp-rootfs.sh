#!/usr/bin/env bash
# POST-DDP: device-proxy rootfs integration gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-DDP rootfs preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${REPO_ROOT}/components/specs/device-driver-proxy.md" "device-driver-proxy spec"

if grep -rq "devices list" "${REPO_ROOT}/components/strawwu-cli" 2>/dev/null; then
    pass "strawwu devices list"
else
    fail "strawwu devices list missing in strawwu-cli"
fi

if find "${REPO_ROOT}/components/strawwu-hub" -iname '*device*' 2>/dev/null | grep -q .; then
    pass "Hub devices page artifact"
else
    fail "Hub devices page missing"
fi

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

#!/usr/bin/env bash
# POST-HW-T1: real hardware Live USB matrix gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-HW-T1 live-usb preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_file "${REPO_ROOT}/docs/plans/hw-matrix-results.json" "hw-matrix-results.json"

python3 - "${REPO_ROOT}/docs/plans/hw-matrix-results.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
entries = p.get("entries") or []
real = [
    e for e in entries
    if (e.get("tier") == "T1" or e.get("environment") == "physical-live")
    and e.get("tests", {}).get("gpu_driver") not in (None, "SKIP")
    and e.get("tests", {}).get("wifi") not in (None, "SKIP")
]
if len(real) >= 3:
    print(f"PASS: T1 real machines {len(real)}")
else:
    print(f"FAIL: T1 real PASS need >=3 got {len(real)}", file=sys.stderr)
    raise SystemExit(1)
PY

echo "ALL CHECKS PASS"

#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
echo "=== POST-HW-T3 wincompat preflight ==="
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_file "${REPO_ROOT}/docs/plans/hw-matrix-results.json" "hw-matrix-results.json"
python3 - "${REPO_ROOT}/docs/plans/hw-matrix-results.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
t3 = [e for e in (p.get("entries") or []) if e.get("tier") == "T3"]
if len(t3) >= 1:
    print(f"PASS: T3 entries {len(t3)}")
else:
    print("FAIL: need >=1 T3 hw-matrix entry", file=sys.stderr)
    raise SystemExit(1)
PY
echo "ALL CHECKS PASS"

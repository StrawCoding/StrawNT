#!/usr/bin/env bash
# POST-HW-T2: installed smoke + suspend + HiDPI gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-HW-T2 installed preflight ==="
require_plan "strawwu-hardware-compatibility-test-matrix.md"
require_file "${REPO_ROOT}/docs/plans/hw-matrix-results.json" "hw-matrix-results.json"

python3 - "${REPO_ROOT}/docs/plans/hw-matrix-results.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
entries = p.get("entries") or []
ok = [
    e for e in entries
    if (e.get("tier") == "T2" or e.get("phase") == "installed-smoke")
    and e.get("tests", {}).get("suspend") == "PASS"
    and e.get("tests", {}).get("hidpi") == "PASS"
]
if len(ok) >= 1:
    print(f"PASS: T2 installed smoke {len(ok)}")
else:
    print(f"FAIL: T2 installed need >=1 full PASS got {len(ok)}", file=sys.stderr)
    raise SystemExit(1)
PY

echo "ALL CHECKS PASS"

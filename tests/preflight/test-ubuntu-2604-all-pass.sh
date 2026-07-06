#!/usr/bin/env bash
# Gate: all 7 Ubuntu 26.04 migration stages must be PASS (run after u26-m7).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
STATUS="${PLANS_DIR}/baselines/ubuntu-2604-status.json"

echo "=== Ubuntu 26.04 migration all-pass gate ==="
require_file "${STATUS}" "ubuntu-2604-status.json"

python3 - "${STATUS}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
stages = data.get("stages", [])
pending = [s["id"] for s in stages if not s.get("pass")]
if pending:
    print(f"FAIL: pending stages: {', '.join(pending)}")
    raise SystemExit(1)
print(f"PASS: all {len(stages)} ubuntu 26.04 stages PASS")
PY

target="${PLANS_DIR}/ubuntu-base-target.json"
python3 - "${target}" <<'PY'
import json, pathlib, sys
t = json.loads(pathlib.Path(sys.argv[1]).read_text())
active = t["active"]
if active["codename"] != "resolute":
    print(f"FAIL: active codename still {active['codename']}, expected resolute")
    raise SystemExit(1)
print(f"PASS: active base is {active['version']} {active['codename']}")
PY

echo "UBUNTU 26.04 ALL-PASS OK"

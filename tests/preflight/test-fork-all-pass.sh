#!/usr/bin/env bash
# Verify all 7 fork migration stages are PASS.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
STATUS="${PLANS_DIR}/baselines/fork-status.json"

echo "=== Fork all-pass gate ==="
require_file "${STATUS}" "fork-status.json"

python3 - "${STATUS}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
stages = data.get("stages", {})
expected = [
    "fork-f1-baseline-snapshot", "fork-f2-manifest-repo", "fork-f3-build-pipeline",
    "fork-f4-package-overlays", "fork-f5-apt-fork-suite", "fork-f6-regression-e2e",
    "fork-f7-closeout",
]
for sid in expected:
    st = stages.get(sid, {})
    assert st.get("status") == "PASS", f"{sid} not PASS: {st.get('status')}"
print(f"PASS: all {len(expected)} fork stages PASS")
PY

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "FORK ALL-PASS OK"

#!/usr/bin/env bash
# Verify Ubuntu 26.04 migration long-task infrastructure.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
HERMES="${HERMES_HOME:-/root/.hermes}"
CFG="${HERMES}/config/task-workers/projects/strawwu.json"

echo "=== Ubuntu 26.04 migration infrastructure ==="
require_plan "strawwu-ubuntu-2604-migration-plan.md"
require_file "${PLANS_DIR}/ubuntu-base-target.json" "ubuntu-base-target.json"
require_file "${PLANS_DIR}/kickoff/U26-AUTO-SEQUENCE.md" "U26-AUTO-SEQUENCE"

for k in U26-M1-base-clone U26-M2-kernel-rebase U26-M3-debs-rebuild U26-M4-suite-migrate \
         U26-M5-techrefs-refresh U26-M6-regression-e2e U26-M7-closeout; do
    require_file "${PLANS_DIR}/kickoff/${k}.md" "kickoff ${k}"
done

python3 - "${CFG}" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
seq = cfg.get("ubuntu_2604_locked_sequence") or []
assert len(seq) == 7, f"expected 7 u26 stages got {len(seq)}"
for sid in seq:
    assert sid in cfg.get("stages", {}), f"missing stage def {sid}"
target = json.loads(pathlib.Path("docs/plans/ubuntu-base-target.json").read_text())
assert target["target"]["codename"] == "resolute"
assert target["target"]["version"].startswith("26.04")
print(f"PASS: ubuntu_2604_locked_sequence {len(seq)} stages")
print(f"PASS: target Ubuntu {target['target']['version']} {target['target']['codename']}")
PY

require_file "${HERMES}/scripts/longtask_ubuntu_2604_transition_next.sh" "u26 transition script"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "UBUNTU 26.04 INFRASTRUCTURE OK"

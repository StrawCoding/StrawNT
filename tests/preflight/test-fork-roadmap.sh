#!/usr/bin/env bash
# Verify Fork base migration long-task infrastructure is registered.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
HERMES="${HERMES_HOME:-/root/.hermes}"
CFG="${HERMES}/config/task-workers/projects/strawwu.json"

echo "=== Fork roadmap infrastructure ==="
require_plan "strawwu-fork-migration-plan.md"
require_file "${REPO_ROOT}/os-image/fork-base/manifest.json" "fork-base manifest"
require_file "${REPO_ROOT}/os-image/fork-base/packages/include.txt" "fork include"
require_file "${REPO_ROOT}/os-image/fork-base/packages/remove.txt" "fork remove"
require_file "${REPO_ROOT}/os-image/fork-base/packages/replace.json" "fork replace"
require_file "${REPO_ROOT}/os-image/scripts/fork-sync-base.sh" "fork-sync-base"
require_file "${REPO_ROOT}/os-image/scripts/fork-baseline-snapshot.sh" "fork-baseline-snapshot"
require_file "${REPO_ROOT}/os-image/scripts/fork-apply-manifest.sh" "fork-apply-manifest"
require_file "${PLANS_DIR}/kickoff/FORK-AUTO-SEQUENCE.md" "FORK-AUTO-SEQUENCE"

for k in FORK-F1-baseline-snapshot FORK-F2-manifest-repo FORK-F3-build-pipeline \
         FORK-F4-package-overlays FORK-F5-apt-fork-suite FORK-F6-regression-e2e \
         FORK-F7-closeout; do
    require_file "${PLANS_DIR}/kickoff/${k}.md" "kickoff ${k}"
done

python3 - "${CFG}" "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
base = json.loads(pathlib.Path(sys.argv[2]).read_text())
fork = cfg.get("fork_locked_sequence") or []
assert len(fork) == 7, f"expected 7 fork stages got {len(fork)}"
assert base.get("fork", {}).get("first_stage") == "fork-f1-baseline-snapshot"
assert base.get("fork", {}).get("trigger_after") == "u26-m7-closeout"
for sid in fork:
    assert sid in cfg.get("stages", {}), f"missing stage def {sid}"
print(f"PASS: fork_locked_sequence {len(fork)} stages")
print(f"PASS: ubuntu-base-target fork config")
PY

require_file "${HERMES}/scripts/longtask_fork_transition_next.sh" "fork transition"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "FORK INFRASTRUCTURE OK"

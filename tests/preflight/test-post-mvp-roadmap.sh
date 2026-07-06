#!/usr/bin/env bash
# Verify Post-MVP long-task infrastructure is registered.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
HERMES="${HERMES_HOME:-/root/.hermes}"
CFG="${HERMES}/config/task-workers/projects/strawwu.json"

echo "=== Post-MVP roadmap infrastructure ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_plan "strawwu-drivers-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-MVP-AUTO-SEQUENCE.md" "POST-MVP-AUTO-SEQUENCE"

for k in POST-D1-strawwu-drivers POST-HW-T1-live-usb POST-HW-T2-installed POST-DDP-rootfs \
         POST-Q3-mfp-smoke POST-D7-software-sources POST-UX-theme-curation POST-V06-closeout \
         POST-UPG-rollback POST-SEC-secureboot-route \
         POST-CI-kernel-selfhosted POST-HW-T3-wincompat POST-Q8-golden-apps POST-V09-engineering-closeout; do
    require_file "${PLANS_DIR}/kickoff/${k}.md" "kickoff ${k}"
done

python3 - "${CFG}" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
seq = cfg.get("post_mvp_locked_sequence") or []
assert len(seq) == 14, f"expected 14 post-mvp stages got {len(seq)}"
u26 = cfg.get("ubuntu_2604_locked_sequence") or []
assert len(u26) == 7, f"expected 7 u26 stages got {len(u26)}"
for sid in seq + u26:
    assert sid in cfg.get("stages", {}), f"missing stage def {sid}"
print(f"PASS: post_mvp_locked_sequence {len(seq)} stages")
print(f"PASS: ubuntu_2604_locked_sequence {len(u26)} stages")
PY

require_file "${HERMES}/scripts/longtask_post_mvp_transition_next.sh" "post-mvp transition"
require_file "${HERMES}/scripts/longtask_ubuntu_2604_transition_next.sh" "u26 transition"
require_plan "strawwu-ubuntu-2604-migration-plan.md"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "POST-MVP INFRASTRUCTURE OK"

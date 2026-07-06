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

for k in POST-D1-strawwu-drivers POST-HW-T1-live-usb POST-HW-T2-installed POST-HW4-peripherals \
         POST-DDP-rootfs POST-Q3-mfp-smoke POST-I2-calamares-luks POST-D7-software-sources \
         POST-UX-theme-curation POST-V06-closeout POST-UPG-rollback POST-SEC-secureboot-route \
         POST-SEC-cve-policy POST-PERF-boot-regression POST-CI-kernel-selfhosted \
         POST-W7-anticheat-substantive POST-HW-T3-wincompat POST-Q8-golden-apps \
         POST-HW5-stable-gate POST-BACKUP-timeshift POST-V09-engineering-closeout; do
    require_file "${PLANS_DIR}/kickoff/${k}.md" "kickoff ${k}"
done

require_plan "strawwu-ubuntu-2604-migration-plan.md"
require_plan "strawwu-fork-migration-plan.md"
require_file "${PLANS_DIR}/kickoff/FORK-AUTO-SEQUENCE.md" "FORK-AUTO-SEQUENCE"

python3 - "${CFG}" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
seq = cfg.get("post_mvp_locked_sequence") or []
assert len(seq) == 21, f"expected 21 post-mvp stages got {len(seq)}"
u26 = cfg.get("ubuntu_2604_locked_sequence") or []
assert len(u26) == 7, f"expected 7 u26 stages got {len(u26)}"
fork = cfg.get("fork_locked_sequence") or []
assert len(fork) == 7, f"expected 7 fork stages got {len(fork)}"
for sid in seq + u26 + fork:
    assert sid in cfg.get("stages", {}), f"missing stage def {sid}"
print(f"PASS: post_mvp_locked_sequence {len(seq)} stages")
print(f"PASS: ubuntu_2604_locked_sequence {len(u26)} stages")
print(f"PASS: fork_locked_sequence {len(fork)} stages")
PY

require_file "${HERMES}/scripts/longtask_post_mvp_transition_next.sh" "post-mvp transition"
require_file "${HERMES}/scripts/longtask_ubuntu_2604_transition_next.sh" "u26 transition"
require_file "${HERMES}/scripts/longtask_fork_transition_next.sh" "fork transition"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "POST-MVP INFRASTRUCTURE OK"

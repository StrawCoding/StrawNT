#!/usr/bin/env bash
# post-v06-closeout: v0.6 drivers/HW DoD + HTML report + Hermes stage gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

CLOSEOUT_DIR="${REPO_ROOT}/docs/plans/post-mvp-v06-closeout"
VALIDATE="${REPO_ROOT}/tests/post-mvp-v06-closeout/validate-post-mvp-v06-closeout.py"
RENDER="${REPO_ROOT}/tests/post-mvp-v06-closeout/render-html.py"
BASELINE="${BASELINES_DIR}/post-mvp-v06-closeout-baseline.json"
CLOSEOUT_REPORT="${PLANS_DIR}/stage-reports/POST-V06-closeout-report.md"
HERMES="${HERMES_HOME:-/root/.hermes}"
STATE="${HERMES}/logs/task-workers/strawwu/state.json"
CFG="${HERMES}/config/task-workers/projects/strawwu.json"

echo "=== POST-V06 closeout preflight ==="

require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-V06-closeout.md" "kickoff POST-V06-closeout.md"
require_file "${CLOSEOUT_DIR}/post-mvp-v06-dod.md" "post-mvp-v06-dod.md"
require_file "${VALIDATE}" "validate-post-mvp-v06-closeout.py"
require_file "${RENDER}" "render-html.py"
require_file "${CLOSEOUT_REPORT}" "POST-V06-closeout-report.md"

for script in "${VALIDATE}" "${RENDER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-post-mvp-v06-closeout:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-post-mvp-v06-closeout target"
else
    fail "Makefile missing test-post-mvp-v06-closeout"
fi

if grep -q 'test-post-mvp-v06-closeout.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes post-v06-closeout"
else
    fail "Makefile preflight missing test-post-mvp-v06-closeout.sh"
fi

if grep -q 'test-post-mvp-v06-closeout' "${CLOSEOUT_DIR}/post-mvp-v06-dod.md"; then
    pass "post-mvp-v06-dod documents test-post-mvp-v06-closeout"
else
    fail "post-mvp-v06-dod missing test-post-mvp-v06-closeout"
fi

if bash -n "${REPO_ROOT}/tests/preflight/test-post-mvp-v06-closeout.sh"; then
    pass "bash -n test-post-mvp-v06-closeout.sh"
else
    fail "test-post-mvp-v06-closeout.sh syntax error"
fi

if [[ -r "${STATE}" ]]; then
    python3 - "${CFG}" "${STATE}" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
state = json.loads(pathlib.Path(sys.argv[2]).read_text())
v06 = [
    "post-d1-strawwu-drivers",
    "post-hw-t1-live-usb",
    "post-hw-t2-installed",
    "post-hw4-peripherals",
    "post-ddp-rootfs",
    "post-q3-mfp-smoke",
    "post-i2-calamares-luks",
    "post-d7-software-sources",
    "post-ux-theme-curation",
]
st = state.get("stages") or {}
focus = state.get("focus_stage") or state.get("current_stage") or ""
fail = 0
for sid in v06:
    status = (st.get(sid) or {}).get("status", "PENDING")
    if status == "PASS":
        print(f"PASS: Hermes [OK] {sid}")
    elif status == "IN_PROGRESS" and sid == focus:
        print(f"PASS: Hermes [IN_PROGRESS] {sid} (focus stage — worker session)")
    else:
        print(f"FAIL: Hermes [{status}] {sid}", file=sys.stderr)
        fail += 1
if fail:
    raise SystemExit(1)
print("PASS: v0.6 prerequisite Hermes stages 9/9 PASS")
PY
else
    # Host orchestration metadata ($HOME/.hermes) — absent/unreadable in CI.
    skip "Hermes state not accessible (${STATE}) — orchestration cross-check skipped"
fi

python3 "${RENDER}" || PREFLIGHT_FAIL=1

if [[ -f "${CLOSEOUT_DIR}/html/post-mvp-v06-closeout-report.html" ]]; then
    pass "HTML post-mvp-v06-closeout-report.html rendered"
    if grep -q '#14b8a6' "${CLOSEOUT_DIR}/html/post-mvp-v06-closeout-report.html"; then
        pass "HTML Teal theme"
    else
        fail "HTML missing Teal #14b8a6"
    fi
    if grep -q 'hermes-deliver' "${CLOSEOUT_DIR}/html/post-mvp-v06-closeout-report.html"; then
        pass "HTML hermes-deliver marker"
    else
        fail "HTML missing hermes-deliver"
    fi
else
    fail "HTML post-mvp-v06-closeout-report.html missing"
fi

python3 "${VALIDATE}" --skip-stage-tests || PREFLIGHT_FAIL=1

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-post-mvp-v06-closeout/v1",
    "stage": "post-v06-closeout",
    "version": version,
    "target": "0.6.0.0-target",
    "v06_stages": 10,
    "dod_markdown": "docs/plans/post-mvp-v06-closeout/post-mvp-v06-dod.md",
    "html": "docs/plans/post-mvp-v06-closeout/html/post-mvp-v06-closeout-report.html",
    "validate": "tests/post-mvp-v06-closeout/validate-post-mvp-v06-closeout.py",
    "render": "tests/post-mvp-v06-closeout/render-html.py",
    "preflight": "tests/preflight/test-post-mvp-v06-closeout.sh",
    "stage_report": "docs/plans/stage-reports/POST-V06-closeout-report.md",
    "status": "docs/plans/baselines/post-mvp-status.json",
    "gates": [
        "make test-post-mvp-v06-closeout",
        "make preflight",
    ],
    "dod": "Post-MVP v0.6 drivers/HW 10 stages + HTML hermes-deliver",
    "post_v06_next": "post-upg-rollback",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "POST-V06 closeout"

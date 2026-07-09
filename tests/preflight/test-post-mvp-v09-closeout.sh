#!/usr/bin/env bash
# post-v09-engineering-closeout: v0.9 engineering DoD + HTML report + Hermes stage gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

CLOSEOUT_DIR="${REPO_ROOT}/docs/plans/post-mvp-v09-closeout"
VALIDATE="${REPO_ROOT}/tests/post-mvp-v09-closeout/validate-post-mvp-v09-closeout.py"
RENDER="${REPO_ROOT}/tests/post-mvp-v09-closeout/render-html.py"
BASELINE="${BASELINES_DIR}/post-mvp-v09-closeout-baseline.json"
CLOSEOUT_REPORT="${PLANS_DIR}/stage-reports/POST-V09-engineering-closeout-report.md"
HERMES="${HERMES_HOME:-/root/.hermes}"
STATE="${HERMES}/logs/task-workers/strawwu/state.json"
CFG="${HERMES}/config/task-workers/projects/strawwu.json"

echo "=== POST-V09 engineering closeout preflight ==="

require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-V09-engineering-closeout.md" "kickoff POST-V09-engineering-closeout.md"
require_file "${CLOSEOUT_DIR}/post-mvp-v09-dod.md" "post-mvp-v09-dod.md"
require_file "${VALIDATE}" "validate-post-mvp-v09-closeout.py"
require_file "${RENDER}" "render-html.py"
require_file "${CLOSEOUT_REPORT}" "POST-V09-engineering-closeout-report.md"

for script in "${VALIDATE}" "${RENDER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-post-mvp-v09-closeout:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-post-mvp-v09-closeout target"
else
    fail "Makefile missing test-post-mvp-v09-closeout"
fi

if grep -q 'test-post-mvp-v09-closeout.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes post-v09-closeout"
else
    fail "Makefile preflight missing test-post-mvp-v09-closeout.sh"
fi

if grep -q 'test-post-mvp-v09-closeout' "${CLOSEOUT_DIR}/post-mvp-v09-dod.md"; then
    pass "post-mvp-v09-dod documents test-post-mvp-v09-closeout"
else
    fail "post-mvp-v09-dod missing test-post-mvp-v09-closeout"
fi

if bash -n "${REPO_ROOT}/tests/preflight/test-post-mvp-v09-closeout.sh"; then
    pass "bash -n test-post-mvp-v09-closeout.sh"
else
    fail "test-post-mvp-v09-closeout.sh syntax error"
fi

if [[ -r "${STATE}" ]]; then
    python3 - "${CFG}" "${STATE}" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
state = json.loads(pathlib.Path(sys.argv[2]).read_text())
v09 = [
    "post-upg-rollback",
    "post-sec-secureboot-route",
    "post-sec-cve-policy",
    "post-perf-boot-regression",
    "post-ci-kernel-selfhosted",
    "post-w7-anticheat-substantive",
    "post-hw-t3-wincompat",
    "post-q8-golden-apps",
    "post-hw5-stable-gate",
    "post-backup-timeshift",
]
st = state.get("stages") or {}
fail = 0
for sid in v09:
    ok = (st.get(sid) or {}).get("status") == "PASS"
    print(f"PASS: Hermes [{('OK' if ok else 'FAIL')}] {sid}" if ok else f"FAIL: Hermes [{('OK' if ok else 'FAIL')}] {sid}")
    if not ok:
        fail += 1
if fail:
    raise SystemExit(1)
print("PASS: v0.9 prerequisite Hermes stages 10/10 PASS")
PY
else
    # Hermes worker state is host orchestration metadata ($HOME/.hermes) — absent
    # /unreadable in CI. Skip the cross-check honestly; the frozen
    # post-mvp-status.json below still gates the prerequisite stages.
    skip "Hermes state not accessible (${STATE}) — orchestration cross-check skipped"
fi

python3 "${RENDER}" || PREFLIGHT_FAIL=1

if [[ -f "${CLOSEOUT_DIR}/html/post-mvp-v09-closeout-report.html" ]]; then
    pass "HTML post-mvp-v09-closeout-report.html rendered"
    if grep -q '#14b8a6' "${CLOSEOUT_DIR}/html/post-mvp-v09-closeout-report.html"; then
        pass "HTML Teal theme"
    else
        fail "HTML missing Teal #14b8a6"
    fi
    if grep -q 'hermes-deliver' "${CLOSEOUT_DIR}/html/post-mvp-v09-closeout-report.html"; then
        pass "HTML hermes-deliver marker"
    else
        fail "HTML missing hermes-deliver"
    fi
else
    fail "HTML post-mvp-v09-closeout-report.html missing"
fi

python3 "${VALIDATE}" --skip-stage-tests || PREFLIGHT_FAIL=1

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-post-mvp-v09-closeout/v1",
    "stage": "post-v09-engineering-closeout",
    "version": version,
    "target": "0.9.0.0-target",
    "v09_stages": 11,
    "dod_markdown": "docs/plans/post-mvp-v09-closeout/post-mvp-v09-dod.md",
    "html": "docs/plans/post-mvp-v09-closeout/html/post-mvp-v09-closeout-report.html",
    "validate": "tests/post-mvp-v09-closeout/validate-post-mvp-v09-closeout.py",
    "render": "tests/post-mvp-v09-closeout/render-html.py",
    "preflight": "tests/preflight/test-post-mvp-v09-closeout.sh",
    "stage_report": "docs/plans/stage-reports/POST-V09-engineering-closeout-report.md",
    "status": "docs/plans/baselines/post-mvp-status.json",
    "gates": [
        "make test-post-mvp-v09-closeout",
        "make test-post-mvp-all-pass",
        "make preflight",
    ],
    "dod": "Post-MVP v0.9 engineering 11 stages + HTML hermes-deliver",
    "post_v09_next": "official-release",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "POST-V09 engineering closeout"

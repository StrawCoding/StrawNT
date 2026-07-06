#!/usr/bin/env bash
# W8-MVP-closeout: MVP DoD + HTML report + wave evidence gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

MVP_DIR="${REPO_ROOT}/docs/plans/mvp-closeout"
VALIDATE="${REPO_ROOT}/tests/mvp-closeout/validate-mvp-closeout.py"
RENDER="${REPO_ROOT}/tests/mvp-closeout/render-html.py"
BASELINE="${BASELINES_DIR}/mvp-closeout-baseline.json"
CLOSEOUT_REPORT="${PLANS_DIR}/stage-reports/W8-MVP-closeout-report.md"

echo "=== W8-MVP closeout preflight ==="

require_plan "strawwu-prd-v0.5.md"
require_plan "strawwu-deferred-scope.md"
require_file "${PLANS_DIR}/kickoff/W8-MVP-closeout.md" "kickoff W8-MVP-closeout.md"
require_file "${MVP_DIR}/mvp-dod.md" "docs/plans/mvp-closeout/mvp-dod.md"
require_file "${VALIDATE}" "validate-mvp-closeout.py"
require_file "${RENDER}" "render-html.py"
require_file "${CLOSEOUT_REPORT}" "W8-MVP-closeout-report.md"

for script in "${VALIDATE}" "${RENDER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-mvp-closeout:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-mvp-closeout target"
else
    fail "Makefile missing test-mvp-closeout"
fi

if grep -q 'test-mvp-closeout.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes mvp-closeout"
else
    fail "Makefile preflight missing test-mvp-closeout.sh"
fi

if grep -q 'test-wave-all-pass' "${MVP_DIR}/mvp-dod.md"; then
    pass "mvp-dod documents test-wave-all-pass"
else
    fail "mvp-dod missing test-wave-all-pass"
fi

if bash -n "${REPO_ROOT}/tests/preflight/test-mvp-closeout.sh"; then
    pass "bash -n test-mvp-closeout.sh"
else
    fail "test-mvp-closeout.sh syntax error"
fi

python3 "${RENDER}" || PREFLIGHT_FAIL=1

if [[ -f "${MVP_DIR}/html/mvp-closeout-report.html" ]]; then
    pass "HTML mvp-closeout-report.html rendered"
    if grep -q '#14b8a6' "${MVP_DIR}/html/mvp-closeout-report.html"; then
        pass "HTML Teal theme"
    else
        fail "HTML missing Teal #14b8a6"
    fi
else
    fail "HTML mvp-closeout-report.html missing"
fi

python3 "${VALIDATE}" || PREFLIGHT_FAIL=1

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-mvp-closeout-baseline/v1",
    "wave": "W8-MVP-closeout",
    "version": version,
    "target_mvp": "0.5.0.0",
    "wave_stages": 47,
    "dod_markdown": "docs/plans/mvp-closeout/mvp-dod.md",
    "html": "docs/plans/mvp-closeout/html/mvp-closeout-report.html",
    "validate": "tests/mvp-closeout/validate-mvp-closeout.py",
    "render": "tests/mvp-closeout/render-html.py",
    "preflight": "tests/preflight/test-mvp-closeout.sh",
    "stage_report": "docs/plans/stage-reports/W8-MVP-closeout-report.md",
    "wave_status": "docs/plans/baselines/wave-status.json",
    "gates": [
        "make test-mvp-closeout",
        "make test-wave-all-pass",
        "make preflight",
    ],
    "dod": "PRD v0.5 MVP §5 + wave 47 stage evidence + HTML hermes-deliver",
    "post_mvp_next": "u26-m1-base-clone",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W8-MVP closeout"

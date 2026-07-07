#!/usr/bin/env bash
# u26-m7-closeout: Ubuntu 26.04 migration DoD + HTML report gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

CLOSEOUT_DIR="${REPO_ROOT}/docs/plans/ubuntu-2604-closeout"
VALIDATE="${REPO_ROOT}/tests/ubuntu-2604-closeout/validate-ubuntu-2604-closeout.py"
RENDER="${REPO_ROOT}/tests/ubuntu-2604-closeout/render-html.py"
BASELINE="${BASELINES_DIR}/ubuntu-2604-closeout-baseline.json"
CLOSEOUT_REPORT="${PLANS_DIR}/stage-reports/U26-M7-closeout-report.md"

echo "=== Ubuntu 26.04 closeout preflight ==="

require_plan "strawwu-ubuntu-2604-migration-plan.md"
require_file "${PLANS_DIR}/kickoff/U26-M7-closeout.md" "kickoff U26-M7-closeout.md"
require_file "${CLOSEOUT_DIR}/ubuntu-2604-dod.md" "ubuntu-2604-dod.md"
require_file "${VALIDATE}" "validate-ubuntu-2604-closeout.py"
require_file "${RENDER}" "render-html.py"
require_file "${CLOSEOUT_REPORT}" "U26-M7-closeout-report.md"

for script in "${VALIDATE}" "${RENDER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-ubuntu-2604-all-pass:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-ubuntu-2604-all-pass target"
else
    fail "Makefile missing test-ubuntu-2604-all-pass"
fi

if bash -n "${REPO_ROOT}/tests/preflight/test-ubuntu-2604-all-pass.sh"; then
    pass "bash -n test-ubuntu-2604-all-pass.sh"
else
    fail "test-ubuntu-2604-all-pass.sh syntax error"
fi

python3 "${RENDER}" || PREFLIGHT_FAIL=1

if [[ -f "${CLOSEOUT_DIR}/html/ubuntu-2604-closeout-report.html" ]]; then
    pass "HTML ubuntu-2604-closeout-report.html rendered"
    if grep -q '#14b8a6' "${CLOSEOUT_DIR}/html/ubuntu-2604-closeout-report.html"; then
        pass "HTML Teal theme"
    else
        fail "HTML missing Teal #14b8a6"
    fi
else
    fail "HTML ubuntu-2604-closeout-report.html missing"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-ubuntu-2604-closeout/v1",
    "stage": "u26-m7-closeout",
    "version": version,
    "target": "26.04.0-resolute",
    "migration_stages": 7,
    "dod_markdown": "docs/plans/ubuntu-2604-closeout/ubuntu-2604-dod.md",
    "html": "docs/plans/ubuntu-2604-closeout/html/ubuntu-2604-closeout-report.html",
    "validate": "tests/ubuntu-2604-closeout/validate-ubuntu-2604-closeout.py",
    "render": "tests/ubuntu-2604-closeout/render-html.py",
    "preflight": "tests/preflight/test-ubuntu-2604-closeout.sh",
    "stage_report": "docs/plans/stage-reports/U26-M7-closeout-report.md",
    "status": "docs/plans/baselines/ubuntu-2604-status.json",
    "gates": [
        "make test-ubuntu-2604-all-pass",
        "make preflight",
    ],
    "dod": "Ubuntu 26.04 resolute migration 7 stages + HTML hermes-deliver",
    "post_migration_next": "post-d1-strawwu-drivers",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "Ubuntu 26.04 closeout"

#!/usr/bin/env bash
# FORK-F7: fork migration closeout — base_mode=fork default + HTML report gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

CLOSEOUT_DIR="${REPO_ROOT}/docs/plans/fork-closeout"
VALIDATE="${REPO_ROOT}/tests/fork-closeout/validate-fork-closeout.py"
RENDER="${REPO_ROOT}/tests/fork-closeout/render-html.py"
BASELINE="${BASELINES_DIR}/fork-closeout-baseline.json"
CLOSEOUT_REPORT="${PLANS_DIR}/stage-reports/FORK-F7-closeout-report.md"
TARGET="${PLANS_DIR}/ubuntu-base-target.json"
MANIFEST="${REPO_ROOT}/os-image/fork-base/manifest.json"

echo "=== FORK-F7 closeout preflight ==="

require_plan "strawwu-fork-migration-plan.md"
require_file "${PLANS_DIR}/kickoff/FORK-F7-closeout.md" "kickoff FORK-F7-closeout.md"
require_file "${CLOSEOUT_DIR}/fork-dod.md" "fork-dod.md"
require_file "${VALIDATE}" "validate-fork-closeout.py"
require_file "${RENDER}" "render-html.py"
require_file "${CLOSEOUT_REPORT}" "FORK-F7-closeout-report.md"

for script in "${VALIDATE}" "${RENDER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

python3 - "${TARGET}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data.get("base_mode") == "fork", f"base_mode must be fork, got {data.get('base_mode')!r}"
print("PASS: ubuntu-base-target.json base_mode=fork")
PY

python3 - "${MANIFEST}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data.get("status") == "active", f"manifest status must be active, got {data.get('status')!r}"
print("PASS: fork-base manifest status=active")
PY

if grep -q 'test-fork-all-pass:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-fork-all-pass target"
else
    fail "Makefile missing test-fork-all-pass"
fi

if grep -q 'test-fork-f7-closeout' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-fork-f7-closeout target"
else
    fail "Makefile missing test-fork-f7-closeout"
fi

if bash -n "${REPO_ROOT}/tests/preflight/test-fork-all-pass.sh"; then
    pass "bash -n test-fork-all-pass.sh"
else
    fail "test-fork-all-pass.sh syntax error"
fi

python3 - "${REPO_ROOT}/os-image/scripts/lib/ubuntu-base-env.sh" "${TARGET}" <<'PY'
import pathlib, subprocess, sys
env = subprocess.run(
    ["bash", "-c", f"source {sys.argv[1]} && load_ubuntu_base_env {pathlib.Path(sys.argv[2]).parent.parent.parent} && echo $STRAWWU_BASE_MODE"],
    capture_output=True, text=True, check=True,
)
mode = env.stdout.strip()
assert mode == "fork", f"STRAWWU_BASE_MODE expected fork got {mode!r}"
print("PASS: STRAWWU_BASE_MODE resolves to fork")
PY

python3 "${RENDER}" || PREFLIGHT_FAIL=1

if [[ -f "${CLOSEOUT_DIR}/html/fork-closeout-report.html" ]]; then
    pass "HTML fork-closeout-report.html rendered"
    if grep -q '#14b8a6' "${CLOSEOUT_DIR}/html/fork-closeout-report.html"; then
        pass "HTML Teal theme"
    else
        fail "HTML missing Teal #14b8a6"
    fi
    if grep -q 'hermes-deliver' "${CLOSEOUT_DIR}/html/fork-closeout-report.html"; then
        pass "HTML hermes-deliver marker"
    else
        fail "HTML missing hermes-deliver"
    fi
else
    fail "HTML fork-closeout-report.html missing"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-fork-closeout/v1",
    "stage": "fork-f7-closeout",
    "version": version,
    "target": "26.04.0-resolute-fork",
    "migration_stages": 7,
    "base_mode": "fork",
    "dod_markdown": "docs/plans/fork-closeout/fork-dod.md",
    "html": "docs/plans/fork-closeout/html/fork-closeout-report.html",
    "validate": "tests/fork-closeout/validate-fork-closeout.py",
    "render": "tests/fork-closeout/render-html.py",
    "preflight": "tests/preflight/test-fork-f7-closeout.sh",
    "stage_report": "docs/plans/stage-reports/FORK-F7-closeout-report.md",
    "status": "docs/plans/baselines/fork-status.json",
    "ubuntu_base_target": "docs/plans/ubuntu-base-target.json",
    "gates": [
        "make test-fork-all-pass",
        "make test-fork-f7-closeout",
        "make preflight",
    ],
    "dod": "Fork 7 stages + base_mode=fork default + HTML hermes-deliver",
    "post_fork_next": "post-d1-strawwu-drivers",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "FORK-F7 closeout"

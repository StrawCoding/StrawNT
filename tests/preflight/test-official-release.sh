#!/usr/bin/env bash
# official-release: Q9 1.0.0 DoD + HTML hermes-deliver gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

CLOSEOUT_DIR="${REPO_ROOT}/docs/plans/official-release"
VALIDATE="${REPO_ROOT}/tests/official-release/validate-official-release.py"
RENDER="${REPO_ROOT}/tests/official-release/render-html.py"
BASELINE="${BASELINES_DIR}/official-release-baseline.json"

echo "=== official-release preflight ==="

# official-release is Q9 / last lock stage — skip until user creates .official-release-authorized.
if [[ ! -f "${REPO_ROOT}/.official-release-authorized" ]]; then
    pass "official-release skipped (no .official-release-authorized)"
    preflight_exit "official-release (skipped)"
fi

require_file "${CLOSEOUT_DIR}/official-release-dod.md" "official-release-dod.md"
require_file "${VALIDATE}" "validate-official-release.py"
require_file "${RENDER}" "render-html.py"
require_file "${REPO_ROOT}/.official-release-authorized" ".official-release-authorized"
require_file "${REPO_ROOT}/.official-release-target" ".official-release-target"

for script in "${VALIDATE}" "${RENDER}"; do
    chmod +x "${script}" 2>/dev/null || true
    pass "$(basename "${script}") ready"
done

if grep -q 'test-official-release:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-official-release target"
else
    fail "Makefile missing test-official-release"
fi

python3 "${RENDER}" || PREFLIGHT_FAIL=1

if [[ -f "${CLOSEOUT_DIR}/html/official-release-report.html" ]]; then
    pass "HTML official-release-report.html rendered"
    grep -q '#14b8a6' "${CLOSEOUT_DIR}/html/official-release-report.html" && pass "HTML Teal theme" || fail "HTML missing Teal"
    grep -q 'hermes-deliver' "${CLOSEOUT_DIR}/html/official-release-report.html" && pass "HTML hermes-deliver" || fail "HTML missing hermes-deliver"
else
    fail "HTML official-release-report.html missing"
fi

python3 "${VALIDATE}" || PREFLIGHT_FAIL=1

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os
version = os.environ["STRAWWU_BASELINE_VERSION"]
print(json.dumps({
    "schema": "strawwu-official-release/v1",
    "stage": "official-release",
    "version": version,
    "target": "1.0.0-target",
    "dod_markdown": "docs/plans/official-release/official-release-dod.md",
    "html": "docs/plans/official-release/html/official-release-report.html",
}, indent=2))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

if [[ "${PREFLIGHT_FAIL:-0}" -eq 1 ]]; then
    echo "=== official-release done: FAIL ==="
    exit 1
fi
echo "=== official-release done: PASS ==="

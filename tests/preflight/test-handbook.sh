#!/usr/bin/env bash
# W8-DOC-handbook: User + admin handbook — DOC2 wincompat + DOC3 upgrade/rescue.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

HANDBOOK="${REPO_ROOT}/docs/user/handbook"
VALIDATE="${REPO_ROOT}/tests/handbook/validate-handbook.py"
RENDER="${REPO_ROOT}/tests/handbook/render-html.py"
BASELINE="${BASELINES_DIR}/handbook-baseline.json"
MANIFEST="${HANDBOOK}/manifest.json"

echo "=== W8-DOC handbook preflight ==="

require_plan "strawwu-user-docs-plan.md"
require_plan "strawwu-prd-v0.5.md"
require_plan "strawwu-deferred-scope.md"

require_file "${HANDBOOK}/README.md" "docs/user/handbook/README.md"
require_file "${HANDBOOK}/user-handbook.md" "docs/user/handbook/user-handbook.md"
require_file "${HANDBOOK}/admin-handbook.md" "docs/user/handbook/admin-handbook.md"
require_file "${HANDBOOK}/wincompat-guide.md" "docs/user/handbook/wincompat-guide.md"
require_file "${HANDBOOK}/upgrade-rescue-guide.md" "docs/user/handbook/upgrade-rescue-guide.md"
require_file "${MANIFEST}" "docs/user/handbook/manifest.json"
require_file "${VALIDATE}" "validate-handbook.py"
require_file "${RENDER}" "render-html.py"

for script in "${VALIDATE}" "${RENDER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-handbook:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-handbook target"
else
    fail "Makefile missing test-handbook"
fi

if grep -q 'test-handbook.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes handbook"
else
    fail "Makefile preflight missing test-handbook.sh"
fi

if grep -q 'handbook' "${REPO_ROOT}/docs/user/README.md"; then
    pass "docs/user/README.md links handbook"
else
    fail "docs/user/README.md missing handbook link"
fi

if grep -q 'TBD' "${HANDBOOK}/README.md"; then
    pass "handbook README community TBD placeholder"
else
    fail "handbook README missing TBD support placeholder"
fi

if grep -q 'strawwu-hub' "${HANDBOOK}/user-handbook.md"; then
    pass "user-handbook documents Hub"
else
    fail "user-handbook missing Hub"
fi

if grep -q 'strawwu-initd' "${HANDBOOK}/admin-handbook.md"; then
    pass "admin-handbook documents initd"
else
    fail "admin-handbook missing initd"
fi

if grep -q 'A/B/C/F\|等級' "${HANDBOOK}/wincompat-guide.md"; then
    pass "wincompat-guide documents compat grades"
else
    fail "wincompat-guide missing compat grades"
fi

if grep -q 'strawwu-upgrade' "${HANDBOOK}/upgrade-rescue-guide.md"; then
    pass "upgrade-rescue-guide documents strawwu-upgrade"
else
    fail "upgrade-rescue-guide missing strawwu-upgrade"
fi

if bash -n "${REPO_ROOT}/tests/preflight/test-handbook.sh"; then
    pass "bash -n test-handbook.sh"
else
    fail "test-handbook.sh syntax error"
fi

python3 "${VALIDATE}" || PREFLIGHT_FAIL=1

for html in user-handbook admin-handbook wincompat-guide upgrade-rescue-guide; do
    if [[ -f "${HANDBOOK}/html/${html}.html" ]]; then
        pass "HTML ${html}.html rendered"
    else
        fail "HTML ${html}.html missing"
    fi
done

validate_json_file "${MANIFEST}"

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-handbook-baseline/v1",
    "wave": "W8-DOC-handbook",
    "version": version,
    "docs_root": "docs/user/handbook",
    "volumes": [
        {"id": "user", "markdown": "user-handbook.md", "html": "html/user-handbook.html"},
        {"id": "admin", "markdown": "admin-handbook.md", "html": "html/admin-handbook.html"},
        {"id": "wincompat", "markdown": "wincompat-guide.md", "html": "html/wincompat-guide.html"},
        {"id": "upgrade-rescue", "markdown": "upgrade-rescue-guide.md", "html": "html/upgrade-rescue-guide.html"},
    ],
    "index": "docs/user/handbook/README.md",
    "manifest": "docs/user/handbook/manifest.json",
    "validate": "tests/handbook/validate-handbook.py",
    "render": "tests/handbook/render-html.py",
    "preflight": "tests/preflight/test-handbook.sh",
    "dod": "user+admin handbook with DOC2 wincompat + DOC3 upgrade/rescue HTML",
    "support_placeholder": "TBD",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W8-DOC handbook"

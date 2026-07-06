#!/usr/bin/env bash
# W6-DOC1: User documentation — install / live / firstboot / rescue guides.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

USER_DOCS="${REPO_ROOT}/docs/user"
VALIDATE="${REPO_ROOT}/tests/user-docs/validate-user-docs.py"
RENDER="${REPO_ROOT}/tests/user-docs/render-html.py"
BASELINE="${BASELINES_DIR}/user-docs-baseline.json"
MANIFEST="${USER_DOCS}/manifest.json"

echo "=== W6-DOC1 user-docs preflight ==="

require_plan "strawwu-user-docs-plan.md"
require_plan "strawwu-prd-v0.5.md"
require_plan "strawwu-deferred-scope.md"

require_file "${USER_DOCS}/README.md" "docs/user/README.md"
require_file "${USER_DOCS}/install-guide.md" "docs/user/install-guide.md"
require_file "${USER_DOCS}/rescue-guide.md" "docs/user/rescue-guide.md"
require_file "${MANIFEST}" "docs/user/manifest.json"
require_file "${VALIDATE}" "validate-user-docs.py"
require_file "${RENDER}" "render-html.py"

for script in "${VALIDATE}" "${RENDER}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-user-docs:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-user-docs target"
else
    fail "Makefile missing test-user-docs"
fi

if grep -q 'test-user-docs.sh' "${REPO_ROOT}/Makefile"; then
    pass "Makefile preflight includes user-docs"
else
    fail "Makefile preflight missing test-user-docs.sh"
fi

if grep -q 'install-guide.md' "${USER_DOCS}/README.md" \
    && grep -q 'rescue-guide.md' "${USER_DOCS}/README.md"; then
    pass "README links install + rescue guides"
else
    fail "README missing guide links"
fi

if grep -q 'TBD' "${USER_DOCS}/README.md"; then
    pass "README community TBD placeholder (deferred scope)"
else
    fail "README missing TBD support placeholder"
fi

if grep -q 'strawwu-firstboot' "${USER_DOCS}/install-guide.md"; then
    pass "install-guide documents firstboot"
else
    fail "install-guide missing firstboot"
fi

if grep -q 'strawwu-initd repair' "${USER_DOCS}/rescue-guide.md"; then
    pass "rescue-guide documents initd repair"
else
    fail "rescue-guide missing initd repair"
fi

if grep -q 'strawwu-target-setup --repair-only' "${USER_DOCS}/rescue-guide.md"; then
    pass "rescue-guide documents target-setup repair"
else
    fail "rescue-guide missing target-setup repair"
fi

if bash -n "${REPO_ROOT}/tests/preflight/test-user-docs.sh"; then
    pass "bash -n test-user-docs.sh"
else
    fail "test-user-docs.sh syntax error"
fi

python3 "${VALIDATE}" || PREFLIGHT_FAIL=1

if [[ -f "${USER_DOCS}/html/install-guide.html" ]] && [[ -f "${USER_DOCS}/html/rescue-guide.html" ]]; then
    pass "HTML guides rendered"
else
    fail "HTML guides missing under docs/user/html/"
fi

validate_json_file "${MANIFEST}"

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-user-docs-baseline/v1",
    "wave": "W6-DOC1",
    "version": version,
    "docs_root": "docs/user",
    "guides": [
        {"id": "install", "markdown": "install-guide.md", "html": "html/install-guide.html"},
        {"id": "rescue", "markdown": "rescue-guide.md", "html": "html/rescue-guide.html"},
    ],
    "index": "docs/user/README.md",
    "manifest": "docs/user/manifest.json",
    "validate": "tests/user-docs/validate-user-docs.py",
    "render": "tests/user-docs/render-html.py",
    "preflight": "tests/preflight/test-user-docs.sh",
    "dod": "docs/user install+rescue guides with HTML hermes-deliver artifacts",
    "support_placeholder": "TBD",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W6-DOC1 user-docs"

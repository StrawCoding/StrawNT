#!/usr/bin/env bash
# R0: App Registry baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== R0 app-registry preflight ==="

require_plan "strawwu-app-registry-plan.md"

if [[ -f "${REPO_ROOT}/components/strawwu-nt/src/installer.rs" ]]; then
    if grep -q 'struct AppDatabase' "${REPO_ROOT}/components/strawwu-nt/src/installer.rs"; then
        pass "AppDatabase stub in strawwu-nt"
    else
        fail "AppDatabase stub missing in strawwu-nt"
    fi
else
    fail "components/strawwu-nt/src/installer.rs missing"
fi

registry_crate="${REPO_ROOT}/components/strawwu-app-registry"
if [[ -d "${registry_crate}" ]]; then
    pass "strawwu-app-registry crate exists"
else
    warn "strawwu-app-registry crate not yet created (Wave R1)"
fi

schema="${REPO_ROOT}/docs/plans/schemas/app-registry.schema.json"
if [[ -f "${schema}" ]]; then
    validate_json_file "${schema}"
else
    warn "app-registry.schema.json pending (Wave R0 schema freeze)"
fi

preflight_exit "R0 app-registry"

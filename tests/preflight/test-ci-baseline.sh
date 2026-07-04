#!/usr/bin/env bash
# CI0: CI / build pipeline baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== CI0 ci-baseline preflight ==="

require_plan "strawwu-ci-build-plan.md"

make_targets=(
    preflight
    preflight-iso-before-boot
    test-phase0
    test-phase2
    test-wincompat
    validate-calamares-preflight
    build-debs
    bump-version
)

for target in "${make_targets[@]}"; do
    if grep -q "^${target}:" "${REPO_ROOT}/Makefile" || grep -q "^${target}:" "${REPO_ROOT}/Makefile" ; then
        pass "Makefile target ${target}"
    else
        fail "Makefile missing target ${target}"
    fi
done

if grep -q 'test-wave0-baseline' "${REPO_ROOT}/Makefile"; then
    pass "Makefile target test-wave0-baseline"
else
    fail "Makefile missing test-wave0-baseline (add in W0)"
fi

ci_dirs=(.github/workflows .gitlab-ci.yml)
found_ci=false
for path in "${ci_dirs[@]}"; do
    if [[ -e "${REPO_ROOT}/${path}" ]]; then
        found_ci=true
        pass "CI config ${path}"
    fi
done
if [[ "${found_ci}" == false ]]; then
    warn "no CI workflow yet (Wave CI1)"
fi

preflight_exit "CI0 ci-baseline"

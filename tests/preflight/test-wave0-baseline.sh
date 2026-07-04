#!/usr/bin/env bash
# Wave 0 aggregate runner: 12 preflight scripts + baseline JSON validation.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== Wave 0 baseline aggregate ==="

scripts=(
    test-init-tools.sh
    test-flatpak.sh
    test-desktop-stack.sh
    test-app-registry.sh
    test-release-baseline.sh
    test-security-baseline.sh
    test-legal-trademark.sh
    test-observability.sh
    test-perf-baseline.sh
    test-ci-baseline.sh
    test-wincompat-os.sh
)

for script in "${scripts[@]}"; do
    echo ""
    echo "--- running ${script} ---"
    bash "${REPO_ROOT}/tests/preflight/${script}" || PREFLIGHT_FAIL=1
done

echo ""
echo "--- validating baseline JSON files ---"
for json in release-baseline.json obs-baseline.json perf-baseline.json; do
    path="${BASELINES_DIR}/${json}"
    if [[ -f "${path}" ]]; then
        validate_json_file "${path}"
    else
        fail "missing baseline ${path}"
    fi
done

preflight_exit "Wave 0 baseline aggregate"

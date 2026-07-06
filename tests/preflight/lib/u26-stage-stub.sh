#!/usr/bin/env bash
# Per-stage preflight stubs for Ubuntu 26.04 migration (expand when stage starts).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
STAGE="${1:?stage script name without test- prefix}"

case "${STAGE}" in
  u26-base-clone)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    require_file "${PLANS_DIR}/ubuntu-base-target.json" "ubuntu-base-target"
    ;;
  u26-kernel-rebase|u26-debs-rebuild|u26-suite-migrate|u26-techrefs-refresh|u26-regression-e2e)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    ;;
  software-sources)
    require_plan "strawwu-d7-software-sources-plan.md"
    ;;
  ux-theme-curation)
    require_plan "strawwu-ux-theme-curation-plan.md"
    ;;
  *)
    echo "unknown stage ${STAGE}" >&2
    exit 1
    ;;
esac

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "PASS: ${STAGE} preflight stub"

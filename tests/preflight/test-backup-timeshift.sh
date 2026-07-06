#!/usr/bin/env bash
# POST-BACKUP: Timeshift / system backup PoC gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-BACKUP timeshift preflight ==="
require_plan "strawwu-backup-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-BACKUP-timeshift.md" "kickoff POST-BACKUP"
require_file "${REPO_ROOT}/os-image/debs/strawwu-backup/DEBIAN/control" "strawwu-backup deb"
require_file "${PLANS_DIR}/stage-reports/POST-BACKUP-timeshift-report.md" "stage report"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

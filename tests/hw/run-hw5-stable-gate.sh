#!/usr/bin/env bash
# POST-HW5: refresh stable_summary in hw-matrix-results.json (T1+T2 real hardware).
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/hw/lib.sh
source "${HW_DIR}/lib.sh"

COMPUTE="${HW_DIR}/compute-stable-summary.py"

hw_log "POST-HW5 stable gate: computing T1+T2 stable_summary"
[[ -f "${COMPUTE}" ]] || hw_die "missing ${COMPUTE}"
chmod +x "${COMPUTE}" 2>/dev/null || true

if ! python3 "${COMPUTE}" "${RESULTS_JSON}"; then
    hw_die "stable_rate < 80% — add/fix T1+T2 real-hardware matrix entries"
fi

hw_log "POST-HW5 stable gate complete → ${RESULTS_JSON}"

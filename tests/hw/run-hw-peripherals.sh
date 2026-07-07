#!/usr/bin/env bash
# POST-HW4: merge fixture/live peripheral entry into hw-matrix-results.json.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

FIXTURE=1
MACHINE_ID="t2-peripheral-intel-laptop"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-fixture) FIXTURE=0; shift ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        -h|--help) echo "Usage: run-hw-peripherals.sh [--no-fixture] [--machine-id ID]"; exit 0 ;;
        *) hw_die "unknown arg: $1" ;;
    esac
done

TMP_ENTRY="$(mktemp)"
trap 'rm -f "${TMP_ENTRY}"' EXIT

args=(--output "${TMP_ENTRY}" --machine-id "${MACHINE_ID}")
if [[ "${FIXTURE}" -eq 1 ]]; then
    args+=(--fixture)
fi

bash "${HW_DIR}/smoke-peripherals.sh" "${args[@]}"
bash "${HW_DIR}/merge-entry.sh" --entry "${TMP_ENTRY}" --machine-id "${MACHINE_ID}"

python3 - <<PY
import json
from pathlib import Path

path = Path("${RESULTS_JSON}")
data = json.loads(path.read_text(encoding="utf-8"))
machines = data.get("machines") or []
periph = [
    m for m in machines
    if any(k in (m.get("tests") or {}) for k in ("touchpad", "fingerprint", "webcam", "peripherals"))
    and (m.get("tests") or {}).get("peripherals") not in (None, "SKIP")
]
print(f"PASS: merged peripheral matrix entries {len(periph)}")
if len(periph) < 1:
    raise SystemExit(1)
PY

hw_log "POST-HW4 peripheral matrix complete → ${RESULTS_JSON}"

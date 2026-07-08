#!/usr/bin/env bash
# POST-HW-T3: merge fixture/live wincompat entry into hw-matrix-results.json.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

FIXTURE=1
MACHINE_ID="t3-wincompat-nvidia-desktop"
GPU_VENDOR="nvidia"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-fixture) FIXTURE=0; shift ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        --gpu-vendor) GPU_VENDOR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: run-hw-t3-wincompat.sh [--no-fixture] [--machine-id ID] [--gpu-vendor VENDOR]"
            exit 0
            ;;
        *) hw_die "unknown arg: $1" ;;
    esac
done

TMP_ENTRY="$(mktemp)"
trap 'rm -f "${TMP_ENTRY}"' EXIT

args=(--output "${TMP_ENTRY}" --machine-id "${MACHINE_ID}" --gpu-vendor "${GPU_VENDOR}")
if [[ "${FIXTURE}" -eq 1 ]]; then
    args+=(--fixture)
fi

bash "${HW_DIR}/smoke-wincompat.sh" "${args[@]}"
bash "${HW_DIR}/merge-entry.sh" --entry "${TMP_ENTRY}" --machine-id "${MACHINE_ID}"

python3 - <<PY
import json
from pathlib import Path

path = Path("${RESULTS_JSON}")
data = json.loads(path.read_text(encoding="utf-8"))
machines = data.get("machines") or []
t3 = [
    m for m in machines
    if m.get("tier") == "T3"
    and (m.get("tests") or {}).get("wincompat_gui") == "PASS"
]
data["wave"] = "POST-HW-T3"
dims = list(data.get("dimensions") or [])
for d in ("wincompat_status", "wincompat_gui", "wincompat_game"):
    if d not in dims:
        dims.append(d)
data["dimensions"] = dims
data["t3_wincompat"] = {
    "minimum": 1,
    "count": len(t3),
    "honest_partial": sum(
        1 for m in t3 if (m.get("tests") or {}).get("wincompat_game") == "PARTIAL"
    ),
}
data["summary"]["wincompat_pass"] = sum(
    1 for m in machines if (m.get("tests") or {}).get("wincompat_aggregate") == "PASS"
)
data["summary"]["wincompat_partial"] = sum(
    1 for m in machines if (m.get("tests") or {}).get("wincompat_aggregate") == "PARTIAL"
)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"PASS: merged T3 wincompat matrix entries {len(t3)}")
if len(t3) < 1:
    raise SystemExit(1)
PY

hw_log "POST-HW-T3 wincompat matrix complete → ${RESULTS_JSON}"

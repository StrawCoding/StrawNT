#!/usr/bin/env bash
# Merge one machine entry JSON into docs/plans/hw-matrix-results.json (Hermes physical session).
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

ENTRY=""
MACHINE_ID=""

usage() {
    cat <<EOF
Usage: merge-entry.sh --entry FILE [--machine-id ID]

Merge a smoke-live.sh --output JSON entry into hw-matrix-results.json.
Replaces existing machine_id if present.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --entry) ENTRY="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) hw_die "unknown arg: $1" ;;
    esac
done

[[ -n "${ENTRY}" && -f "${ENTRY}" ]] || hw_die "missing --entry FILE"

python3 - <<PY
import json, sys
from pathlib import Path
from datetime import datetime, timezone

entry_path = Path("${ENTRY}")
results_path = Path("${RESULTS_JSON}")

entry = json.loads(entry_path.read_text(encoding="utf-8"))
if "${MACHINE_ID}":
    entry["machine_id"] = "${MACHINE_ID}"

mid = entry.get("machine_id")
if not mid:
    print("FAIL: entry missing machine_id", file=sys.stderr)
    sys.exit(1)

if results_path.is_file():
    data = json.loads(results_path.read_text(encoding="utf-8"))
else:
    data = {
        "schema": "${MATRIX_SCHEMA}",
        "wave": "${MATRIX_WAVE}",
        "version": "${VERSION}",
        "updated": "",
        "iso": "",
        "dimensions": ["gpu", "wifi", "suspend", "hidpi"],
        "minimum_live_pass": int("${MIN_LIVE_PASS}"),
        "minimum_hw_pass": {
            "gpu_driver": int("${MIN_GPU_PASS}"),
            "wifi": int("${MIN_WIFI_PASS}"),
            "suspend": 0,
            "hidpi": 0,
        },
        "machines": [],
        "summary": {},
    }

machines = [m for m in data.get("machines", []) if m.get("machine_id") != mid]
machines.append(entry)
data["machines"] = machines
data["schema"] = data.get("schema", "${MATRIX_SCHEMA}")
data["wave"] = data.get("wave", "${MATRIX_WAVE}")
data["version"] = "${VERSION}"
data["updated"] = datetime.now().astimezone().isoformat(timespec="seconds")

def count_test(key, want):
    return sum(1 for m in machines if m.get("tests", {}).get(key) == want)

data["summary"] = {
    "total": len(machines),
    "live_pass": count_test("live_boot", "PASS"),
    "live_fail": count_test("live_boot", "FAIL"),
    "gpu_pass": count_test("gpu_driver", "PASS"),
    "wifi_pass": count_test("wifi", "PASS"),
    "suspend_pass": count_test("suspend", "PASS"),
    "suspend_skip": count_test("suspend", "SKIP"),
    "hidpi_pass": count_test("hidpi", "PASS"),
    "hidpi_skip": count_test("hidpi", "SKIP"),
}

results_path.parent.mkdir(parents=True, exist_ok=True)
with open(results_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"PASS: merged machine_id={mid} into {results_path}")
PY

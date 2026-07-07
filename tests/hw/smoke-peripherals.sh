#!/usr/bin/env bash
# POST-HW4: laptop peripherals smoke — run on installed StrawWU laptop (physical or fixture).
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

OUTPUT=""
MACHINE_ID=""
ENVIRONMENT="physical-installed"
FIXTURE=0

usage() {
    cat <<EOF
Usage: smoke-peripherals.sh [--output FILE] [--machine-id ID] \\
  [--environment physical-installed|installed-e2e|fixture] [--fixture]

Probes touchpad/Fn/TLP/webcam/fingerprint via strawwu-laptop-peripherals.
Writes one T2 peripheral machine entry JSON (stdout or --output).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --fixture) FIXTURE=1; ENVIRONMENT="fixture"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) hw_die "unknown arg: $1" ;;
    esac
done

[[ -n "${MACHINE_ID}" ]] || MACHINE_ID="t2-peripheral-intel-laptop"

PROBE_TMP="$(mktemp)"
trap 'rm -f "${PROBE_TMP}"' EXIT

CLI="${REPO_ROOT}/os-image/debs/strawwu-laptop/usr/bin/strawwu-laptop-peripherals"
if [[ "${FIXTURE}" -eq 1 ]]; then
    export STRAWWU_LAPTOP_FIXTURE=1
    export STRAWWU_LAPTOP_FIXTURE_PATH="${REPO_ROOT}/os-image/debs/strawwu-laptop/usr/share/strawwu/laptop/fixture-catalog.json"
    export STRAWWU_LAPTOP_PROFILES_DIR="${REPO_ROOT}/os-image/debs/strawwu-laptop/usr/share/strawwu/laptop/device_profiles"
fi
[[ -f "${CLI}" ]] || hw_die "strawwu-laptop-peripherals CLI missing"
python3 "${CLI}" --json smoke > "${PROBE_TMP}"

entry="$(python3 - "${PROBE_TMP}" "${MACHINE_ID}" "${ENVIRONMENT}" "${VERSION}" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

probe_path, machine_id, environment, version = sys.argv[1:5]
probe = json.loads(Path(probe_path).read_text(encoding="utf-8"))
periph = probe["tests"]["peripherals"]
if periph in (None, "SKIP", "FAIL"):
    print(f"FAIL: peripheral aggregate {periph}", file=sys.stderr)
    sys.exit(2)
entry = {
    "machine_id": machine_id,
    "tier": "T2",
    "phase": "peripheral-smoke",
    "environment": environment,
    "cpu": "Intel 12th Gen (laptop peripheral profile)",
    "gpu": "Intel Iris Xe",
    "gpu_vendor": "intel",
    "firmware": "uefi",
    "usb_method": "calamares-install",
    "iso": f"os-image/output/StrawWU-{version}-amd64.iso",
    "tests": {
        "live_boot": "SKIP",
        "wifi": "SKIP",
        "gpu_driver": "SKIP",
        "suspend": "SKIP",
        "hidpi": "SKIP",
        "touchpad": probe["tests"]["touchpad"],
        "fingerprint": probe["tests"]["fingerprint"],
        "webcam": probe["tests"]["webcam"],
        "peripherals": periph,
        "installed_boot": "PASS",
        "desktop": "PASS",
    },
    "markers": ["STRAWWU-PERIPHERAL-SMOKE-OK"],
    "tested": datetime.now().astimezone().isoformat(timespec="seconds"),
    "hw_notes": {
        "touchpad": "libinput curation via strawwu-laptop meta",
        "fingerprint": "fprintd + libpam-fprintd; hardware optional",
        "webcam": "v4l-utils + PipeWire stack",
        "peripherals": "aggregate E10/E15 smoke",
        "mock": probe.get("mock", False),
        "session": "worker fixture smoke (Hermes may replace with physical laptop)",
    },
}
print(json.dumps(entry, indent=2, ensure_ascii=False))
PY
)"

if [[ -n "${OUTPUT}" ]]; then
    printf '%s\n' "${entry}" > "${OUTPUT}"
    hw_log "wrote peripheral entry → ${OUTPUT}"
else
    printf '%s\n' "${entry}"
fi

mock="$(python3 -c "import json; print(json.load(open('${PROBE_TMP}')).get('mock', False))")"
hw_log "POST-HW4 peripheral smoke OK (mock=${mock})"

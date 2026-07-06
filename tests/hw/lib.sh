#!/usr/bin/env bash
# Shared helpers for StrawWU hardware / Live USB matrix tests.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${HW_DIR}/../.." && pwd)}"
OUTPUT_DIR="${REPO_ROOT}/tests/hw/output"
RESULTS_JSON="${REPO_ROOT}/docs/plans/hw-matrix-results.json"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.4.0.0)}"

MARKER_BOOT="${STRAWWU_HW_BOOT_MARKER:-STRAWWU_BOOT_OK}"
MARKER_DESKTOP="${STRAWWU_HW_DESKTOP_MARKER:-STRAWWU-DESKTOP-OK}"
MIN_LIVE_PASS="${STRAWWU_HW_MIN_LIVE_PASS:-3}"

hw_log() { echo "==> $*" >&2; }
hw_die() { echo "ERROR: $*" >&2; exit 1; }

resolve_iso_path() {
    if [[ -n "${STRAWWU_ISO_PATH:-}" && -f "${STRAWWU_ISO_PATH}" ]]; then
        echo "${STRAWWU_ISO_PATH}"
        return
    fi
    local candidate="${REPO_ROOT}/os-image/output/StrawWU-${VERSION}-amd64.iso"
    if [[ -f "${candidate}" ]]; then
        echo "${candidate}"
        return
    fi
    local newest
    newest="$(find "${REPO_ROOT}/os-image/output" -maxdepth 1 -name 'StrawWU-*-amd64.iso' -type f 2>/dev/null \
        | sort -V | tail -1 || true)"
    if [[ -n "${newest}" && -f "${newest}" ]]; then
        hw_log "WARN: no ISO for VERSION=${VERSION}; using ${newest}"
        echo "${newest}"
        return
    fi
    hw_die "no StrawWU ISO found (set STRAWWU_ISO_PATH or run make release-iso)"
}

find_ovmf_code() {
    for p in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF_CODE.fd; do
        [[ -f "$p" ]] && { echo "$p"; return; }
    done
    hw_die "OVMF firmware not found (install ovmf package)"
}

find_ovmf_vars() {
    for p in \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/ovmf/OVMF_VARS.fd; do
        [[ -f "$p" ]] && { echo "$p"; return; }
    done
    hw_die "OVMF vars not found (install ovmf package)"
}

check_serial_markers() {
    local serial_log="$1"
    local boot="FAIL" desktop="FAIL"
    grep -q "${MARKER_BOOT}" "${serial_log}" 2>/dev/null && boot="PASS"
    grep -q "${MARKER_DESKTOP}" "${serial_log}" 2>/dev/null && desktop="PASS"
    printf '%s %s' "${boot}" "${desktop}"
}

write_matrix_results() {
    local version="$1"
    local machines_json="$2"
    local tested="$3"
    local iso="$4"
    local tmp_json
    tmp_json="$(mktemp)"
    printf '%s' "${machines_json}" > "${tmp_json}"

    python3 - <<PY
import json, os
from pathlib import Path

machines = json.loads(Path("${tmp_json}").read_text(encoding="utf-8"))
live_pass = sum(1 for m in machines if m.get("tests", {}).get("live_boot") == "PASS")
live_fail = sum(1 for m in machines if m.get("tests", {}).get("live_boot") == "FAIL")

data = {
    "schema": "strawwu-hw-matrix-results/v1",
    "wave": "W6-HW1",
    "version": "${version}",
    "updated": "${tested}",
    "iso": "${iso}",
    "minimum_live_pass": int("${MIN_LIVE_PASS}"),
    "machines": machines,
    "summary": {
        "total": len(machines),
        "live_pass": live_pass,
        "live_fail": live_fail,
    },
}

out = "${RESULTS_JSON}"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

min_pass = int("${MIN_LIVE_PASS}")
if live_pass < min_pass:
    print(f"FAIL: live_pass={live_pass} < minimum={min_pass}", flush=True)
    raise SystemExit(1)
print(f"PASS: hw-matrix-results.json written ({live_pass}/{len(machines)} live PASS)", flush=True)
PY
    rm -f "${tmp_json}"
}

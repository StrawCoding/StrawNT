#!/usr/bin/env bash
# PERF0: Performance / size baseline + perf-baseline.json.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== PERF0 perf-baseline preflight ==="

require_plan "strawwu-performance-budget-plan.md"

iso_bytes=0
latest_iso=""
if [[ -d "${REPO_ROOT}/os-image/output" ]]; then
    latest_iso="$(find "${REPO_ROOT}/os-image/output" -maxdepth 1 -name 'StrawWU-*.iso' -printf '%p\n' 2>/dev/null | sort | tail -1 || true)"
    if [[ -n "${latest_iso}" && -f "${latest_iso}" ]]; then
        iso_bytes="$(stat -c '%s' "${latest_iso}")"
        pass "latest ISO size bytes=${iso_bytes}"
    else
        warn "no ISO artifact found"
    fi
fi

squashfs_bytes=0
if has_squashfs; then
    squashfs_bytes="$(du -sb "${SQUASHFS_ROOT}" 2>/dev/null | awk '{print $1}')"
    pass "squashfs size bytes=${squashfs_bytes}"
else
    warn "squashfs missing"
fi

python3 - "${BASELINES_DIR}/perf-baseline.json" "${VERSION}" "${iso_bytes}" "${squashfs_bytes}" "${latest_iso}" <<'PY'
import json, sys
from pathlib import Path

out, version, iso_bytes, squashfs_bytes, latest_iso = sys.argv[1:6]
iso_bytes = int(iso_bytes or 0)
squashfs_bytes = int(squashfs_bytes or 0)
gb = lambda b: round(b / (1024**3), 2)

data = {
    "schema": "strawwu-perf-baseline/v1",
    "generated_at": "2026-07-04",
    "version": version,
    "measurements": {
        "latest_iso_bytes": iso_bytes,
        "latest_iso_gb": gb(iso_bytes) if iso_bytes else None,
        "latest_iso_file": Path(latest_iso).name if latest_iso else None,
        "squashfs_bytes": squashfs_bytes,
        "squashfs_gb": gb(squashfs_bytes) if squashfs_bytes else None,
        "live_boot_to_plymouth_sec": None,
        "installed_idle_ram_mb": None,
        "firstboot_complete_sec": None,
    },
    "budgets_v05": {
        "release_iso_max_gb": 7.0,
        "live_boot_to_plymouth_max_sec": 45,
        "installed_idle_ram_max_mb": 2500,
        "firstboot_complete_max_sec": 180,
    },
    "wave0_gaps": [
        "boot-time not measured yet",
        "idle RAM not measured yet",
        "firstboot duration not measured yet",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

pass "baseline written ${BASELINES_DIR}/perf-baseline.json"
validate_json_file "${BASELINES_DIR}/perf-baseline.json"

if [[ "${iso_bytes}" -gt 0 ]]; then
    iso_gb="$(python3 -c "print(round(${iso_bytes}/(1024**3), 2))")"
    if python3 -c "import sys; sys.exit(0 if float('${iso_gb}') <= 7.0 else 1)"; then
        pass "ISO size within 7GB budget (${iso_gb} GB)"
    else
        warn "ISO size ${iso_gb} GB exceeds 7GB budget (track in PERF1)"
    fi
fi

preflight_exit "PERF0 perf-baseline"

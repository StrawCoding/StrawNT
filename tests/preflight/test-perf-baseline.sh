#!/usr/bin/env bash
# PERF0+PERF1: Performance / size baseline + perf-baseline.json + ISO size gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== PERF0+PERF1 perf-baseline preflight ==="

require_plan "strawwu-performance-budget-plan.md"

PERF_GATE="${STRAWWU_PERF_GATE:-advisory}"
pass "PERF gate mode=${PERF_GATE}"

OUTPUT_DIR="${STRAWWU_OUTPUT_DIR:-${REPO_ROOT}/os-image/output}"

iso_bytes=0
latest_iso=""
if [[ -d "${OUTPUT_DIR}" ]]; then
    latest_iso="$(find "${OUTPUT_DIR}" -maxdepth 1 -name 'StrawWU-*.iso' -printf '%p\n' 2>/dev/null | sort | tail -1 || true)"
    if [[ -n "${latest_iso}" && -f "${latest_iso}" ]]; then
        iso_bytes="$(stat -c '%s' "${latest_iso}")"
        pass "latest ISO size bytes=${iso_bytes} (${latest_iso#${REPO_ROOT}/})"
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

perf1_status="skipped"
perf1_note="no ISO artifact"
if [[ "${iso_bytes}" -gt 0 ]]; then
    iso_gb="$(python3 -c "print(round(${iso_bytes}/(1024**3), 2))")"
    if python3 -c "import sys; sys.exit(0 if float('${iso_gb}') <= 7.0 else 1)"; then
        perf1_status="pass"
        perf1_note="ISO ${iso_gb} GB within 7GB budget"
        pass "PERF1 ISO size within 7GB budget (${iso_gb} GB)"
    elif [[ "${PERF_GATE}" == "strict" ]]; then
        perf1_status="fail"
        perf1_note="ISO ${iso_gb} GB exceeds 7GB budget"
        fail "PERF1 strict gate: ISO size ${iso_gb} GB exceeds 7GB budget"
    else
        perf1_status="advisory"
        perf1_note="ISO ${iso_gb} GB exceeds 7GB budget (advisory)"
        warn "ISO size ${iso_gb} GB exceeds 7GB budget (advisory mode)"
    fi
elif [[ "${PERF_GATE}" == "strict" ]]; then
    perf1_status="fail"
    perf1_note="strict gate requires ISO artifact"
    fail "PERF1 strict gate requires ISO artifact"
else
    warn "no ISO artifact (PERF1 size gate skipped in advisory mode)"
fi

python3 - "${BASELINES_DIR}/perf-baseline.json" "${VERSION}" "${iso_bytes}" "${squashfs_bytes}" "${latest_iso}" "${perf1_status}" "${perf1_note}" "${PERF_GATE}" <<'PY'
import json, sys
from pathlib import Path

out, version, iso_bytes, squashfs_bytes, latest_iso, perf1_status, perf1_note, perf_gate = sys.argv[1:9]
iso_bytes = int(iso_bytes or 0)
squashfs_bytes = int(squashfs_bytes or 0)
gb = lambda b: round(b / (1024**3), 2)

data = {
    "schema": "strawwu-perf-baseline/v1",
    "generated_at": "2026-07-06",
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
    "phases": {
        "PERF0": {"status": "complete", "artifact": "perf-baseline.json"},
        "PERF1": {
            "status": "complete" if perf1_status in ("pass", "advisory", "skipped") else "fail",
            "gate_mode": perf_gate,
            "last_result": perf1_status,
            "note": perf1_note,
            "ci_workflow": "release.yml (STRAWWU_PERF_GATE=strict after release-iso)",
        },
        "PERF2": {"status": "deferred", "note": "boot-time regression gate"},
    },
    "wave0_gaps": [
        "boot-time not measured yet (PERF2)",
        "idle RAM not measured yet (PERF2)",
        "firstboot duration not measured yet (PERF2)",
    ],
}
boot_baseline = Path(out).parent / "boot-time-baseline.json"
if boot_baseline.is_file():
    boot = json.loads(boot_baseline.read_text(encoding="utf-8"))
    plymouth = (boot.get("baseline") or {}).get("plymouth_sec")
    if plymouth is not None:
        data["measurements"]["live_boot_to_plymouth_sec"] = plymouth
        data["phases"]["PERF2"] = {
            "status": "complete",
            "artifact": "boot-time-baseline.json",
            "note": "boot-time regression gate (managed by test-perf-boot-regression)",
        }
        data["wave0_gaps"] = [
            g for g in data["wave0_gaps"]
            if "boot-time" not in g
        ]
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

if [[ -z "${STRAWWU_OUTPUT_DIR:-}" ]]; then
    pass "baseline written ${BASELINES_DIR}/perf-baseline.json"
    validate_json_file "${BASELINES_DIR}/perf-baseline.json"
else
    pass "baseline JSON skipped (isolated STRAWWU_OUTPUT_DIR test)"
fi

preflight_exit "PERF0+PERF1 perf-baseline"

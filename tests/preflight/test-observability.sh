#!/usr/bin/env bash
# OBS0: Observability baseline + obs-baseline.json.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== OBS0 observability preflight ==="

require_plan "strawwu-observability-debug-plan.md"

required_codes=(SWU-BT-001 SWU-IN-002 SWU-FB-003 SWU-AR-004 SWU-UP-005 SWU-WC-006)
for code in "${required_codes[@]}"; do
    if grep -q "${code}" "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
        pass "error code documented ${code}"
    else
        fail "missing error code ${code} in observability plan"
    fi
done

log_paths=(
    boot-selfcheck:/var/log/strawwu/boot-selfcheck.log
    install:/var/log/strawwu/install.log
    target-setup:/var/log/strawwu/target-setup.log
    firstboot:/var/log/strawwu/firstboot.log
    app-registry:/var/log/strawwu/app-registry.log
    update:/var/log/strawwu/update.log
    wincompat:/var/log/strawwu/wincompat.log
)

branding_selfcheck="${REPO_ROOT}/os-image/config/branding/usr/local/sbin/strawwu-boot-selfcheck"
if [[ -x "${branding_selfcheck}" ]] || [[ -f "${branding_selfcheck}" ]]; then
    pass "boot-selfcheck script in branding overlay"
else
    fail "boot-selfcheck script missing from branding"
fi

bug_reporter_dir="${REPO_ROOT}/os-image/debs/strawwu-bug-reporter"
schema_ready=false
if [[ -f "${bug_reporter_dir}/usr/lib/strawwu-bug-reporter/bundle.py" ]]; then
    schema_ready=true
fi

python3 - "${BASELINES_DIR}/obs-baseline.json" "${VERSION}" "${schema_ready}" <<'PY'
import json, sys
from pathlib import Path

out, version, schema_ready_str = sys.argv[1:4]
schema_ready = schema_ready_str.lower() == "true"
data = {
    "schema": "strawwu-obs-baseline/v1",
    "generated_at": "2026-07-04",
    "version": version,
    "log_paths": {
        "boot-selfcheck": "/var/log/strawwu/boot-selfcheck.log",
        "install": "/var/log/strawwu/install.log",
        "target-setup": "/var/log/strawwu/target-setup.log",
        "firstboot": "/var/log/strawwu/firstboot.log",
        "app-registry": "/var/log/strawwu/app-registry.log",
        "update": "/var/log/strawwu/update.log",
        "wincompat": "/var/log/strawwu/wincompat.log",
    },
    "error_codes": [
        "SWU-BT-001", "SWU-IN-001", "SWU-IN-002", "SWU-FB-001",
        "SWU-FB-003", "SWU-AR-004", "SWU-UP-005", "SWU-WC-006",
        "SWU-FP-007", "SWU-RE-008",
    ],
    "bug_bundle": {
        "format": "bundle.strawwu-bug",
        "auto_upload_default": False,
        "consent_required": True,
        "schema_ready": schema_ready,
    },
    "wave0_gaps": [
        "/var/log/strawwu/ not yet created in rootfs" if not schema_ready else None,
        "bug bundle CLI not implemented" if not schema_ready else None,
        "structured JSON logging not wired",
    ],
}
data["wave0_gaps"] = [g for g in data["wave0_gaps"] if g]
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

pass "baseline written ${BASELINES_DIR}/obs-baseline.json"
validate_json_file "${BASELINES_DIR}/obs-baseline.json"

preflight_exit "OBS0 observability"

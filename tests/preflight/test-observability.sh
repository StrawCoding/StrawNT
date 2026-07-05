#!/usr/bin/env bash
# OBS0+OBS1: Observability baseline — log paths, error codes, bug bundle schema + CLI.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== OBS1 observability preflight ==="

require_plan "strawwu-observability-debug-plan.md"

required_codes=(SWU-BT-001 SWU-IN-002 SWU-FB-003 SWU-AR-004 SWU-UP-005 SWU-WC-006)
for code in "${required_codes[@]}"; do
    if grep -q "${code}" "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
        pass "error code documented ${code}"
    else
        fail "missing error code ${code} in observability plan"
    fi
done

branding_selfcheck="${REPO_ROOT}/os-image/config/branding/usr/local/sbin/strawwu-boot-selfcheck"
if [[ -x "${branding_selfcheck}" ]] || [[ -f "${branding_selfcheck}" ]]; then
    pass "boot-selfcheck script in branding overlay"
else
    fail "boot-selfcheck script missing from branding"
fi

# OBS1: bug bundle schema + CLI
DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-bug-reporter"
BUNDLE_PY="${DEB_DIR}/usr/lib/strawwu-bug-reporter/bundle.py"
CLI="${DEB_DIR}/usr/bin/strawwu-bug-report"

require_file "${BUNDLE_PY}" "OBS1 bundle.py"
require_file "${CLI}" "OBS1 strawwu-bug-report CLI"

for entry in manifest.json system.json journal.txt dmesg.txt user-notes.txt; do
    if grep -q "${entry}" "${BUNDLE_PY}"; then
        pass "bundle schema includes ${entry}"
    else
        fail "bundle.py missing ${entry}"
    fi
done

if grep -q 'bundle.strawwu-bug' "${BUNDLE_PY}"; then
    pass "bundle format bundle.strawwu-bug"
else
    fail "bundle format not defined"
fi

if grep -q 'validate_bundle' "${BUNDLE_PY}"; then
    pass "bundle validate_bundle function"
else
    fail "bundle.py missing validate_bundle"
fi

chmod +x "${CLI}" 2>/dev/null || true
tmp_bundle="$(mktemp --suffix=.strawwu-bug)"
trap 'rm -f "${tmp_bundle}"' EXIT

if "${CLI}" --dry-run; then
    pass "OBS1 CLI dry-run"
else
    fail "OBS1 CLI dry-run"
fi

if "${CLI}" -o "${tmp_bundle}" --notes "obs1-preflight"; then
    pass "OBS1 CLI bundle create"
else
    fail "OBS1 CLI bundle create"
fi

if "${CLI}" --validate "${tmp_bundle}"; then
    pass "OBS1 CLI bundle validate"
else
    fail "OBS1 CLI bundle validate"
fi

python3 - "${BASELINES_DIR}/obs-baseline.json" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
data = {
    "schema": "strawwu-obs-baseline/v1",
    "generated_at": "2026-07-05",
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
        "schema_ready": True,
        "cli": "strawwu-bug-report",
        "entries": [
            "manifest.json", "system.json", "journal.txt",
            "dmesg.txt", "logs/", "registry.json", "user-notes.txt",
        ],
    },
    "wave0_gaps": [
        "structured JSON logging not wired",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

pass "baseline written ${BASELINES_DIR}/obs-baseline.json"
validate_json_file "${BASELINES_DIR}/obs-baseline.json"

preflight_exit "OBS1 observability"

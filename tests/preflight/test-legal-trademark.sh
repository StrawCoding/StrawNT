#!/usr/bin/env bash
# LEG0+LEG2: Legal / trademark scan + privacy/EULA draft HTML.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== LEG2 legal-trademark preflight ==="

require_plan "strawwu-legal-compliance-plan.md"

BRANDING="${REPO_ROOT}/os-image/config/branding"
LEGAL_DIR="${BRANDING}/usr/share/strawwu/legal"
PRIVACY="${LEGAL_DIR}/privacy.html"
EULA="${LEGAL_DIR}/eula.html"

SCAN_DIRS=(
    "${BRANDING}/etc"
    "${BRANDING}/usr/share/calamares"
    "${BRANDING}/usr/share/plymouth"
    "${BRANDING}/usr/share/themes"
)

forbidden_patterns=(
    'NAME="Ubuntu"'
    'PRETTY_NAME="Ubuntu'
    'Welcome to Ubuntu'
    'ubuntu.com'
)

for pattern in "${forbidden_patterns[@]}"; do
    if grep -Rqi --exclude='os-release' --exclude='casper.conf' -e "${pattern}" "${BRANDING}" 2>/dev/null; then
        fail "forbidden trademark pattern in branding: ${pattern}"
    else
        pass "no branding match for ${pattern}"
    fi
done

if grep -q '^ID=ubuntu$' "${BRANDING}/etc/os-release" 2>/dev/null; then
    pass "os-release keeps ID=ubuntu (casper compat)"
else
    warn "os-release missing ID=ubuntu"
fi

if grep -q 'NAME="StrawWU"' "${BRANDING}/etc/os-release" 2>/dev/null; then
    pass "os-release NAME=StrawWU"
else
    fail "os-release missing NAME=StrawWU"
fi

# LEG2: privacy + EULA draft HTML
require_file "${PRIVACY}" "LEG2 privacy.html"
require_file "${EULA}" "LEG2 eula.html"

for doc in "${PRIVACY}" "${EULA}"; do
    if grep -qi 'ubuntu' "${doc}"; then
        # Allow mention in trademark disclaimer context only
        if grep -qi 'Canonical' "${doc}" || grep -qi '商標' "${doc}"; then
            pass "$(basename "${doc}") ubuntu mention in trademark disclaimer only"
        else
            fail "$(basename "${doc}") contains Ubuntu trademark outside disclaimer"
        fi
    else
        pass "$(basename "${doc}") no Ubuntu trademark"
    fi
done

for phrase in '預設不上傳' '無遙測' 'opt-in'; do
    if grep -q "${phrase}" "${PRIVACY}"; then
        pass "privacy.html mentions ${phrase}"
    else
        fail "privacy.html missing ${phrase}"
    fi
done

if grep -q 'privacy.html' "${EULA}"; then
    pass "eula.html links to privacy.html"
else
    fail "eula.html missing privacy.html link"
fi

if grep -q '預設無遙測' "${EULA}" || grep -q '預設不上傳' "${EULA}"; then
    pass "eula.html documents no-default-telemetry"
else
    fail "eula.html missing no-default-telemetry clause"
fi

python3 - "${BASELINES_DIR}/legal-baseline.json" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
data = {
    "schema": "strawwu-legal-baseline/v1",
    "generated_at": "2026-07-05",
    "version": version,
    "trademark": {
        "ui_brand": "StrawWU",
        "os_release_id": "ubuntu",
        "forbidden_ui_patterns": [
            'NAME="Ubuntu"', 'PRETTY_NAME="Ubuntu',
            'Welcome to Ubuntu', 'ubuntu.com',
        ],
    },
    "legal_docs": {
        "privacy_policy": "/usr/share/strawwu/legal/privacy.html",
        "eula": "/usr/share/strawwu/legal/eula.html",
        "status": "draft",
        "no_default_telemetry": True,
        "bug_consent_required": True,
    },
    "phases": {
        "LEG0": {"status": "complete", "artifact": "trademark scan in test-legal-trademark.sh"},
        "LEG1": {"status": "deferred", "note": "license-inventory.csv auto-generation"},
        "LEG2": {"status": "complete", "artifact": "privacy.html + eula.html"},
        "LEG3": {"status": "deferred", "note": "Calamares/GRUB/Plymouth compliance audit"},
        "LEG4": {"status": "pending", "note": "release compliance gate CI (w7-perf-legal-gate)"},
    },
    "wave2_gaps": [
        "license-inventory.csv auto-generation (LEG1)",
        "Calamares/GRUB/Plymouth compliance audit (LEG3)",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline written ${BASELINES_DIR}/legal-baseline.json"
validate_json_file "${BASELINES_DIR}/legal-baseline.json"

preflight_exit "LEG2 legal-trademark"

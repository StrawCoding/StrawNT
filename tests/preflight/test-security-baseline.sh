#!/usr/bin/env bash
# SEC0+SEC2: Security / trust baseline — telemetry purge + bug-reporter privacy/consent.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== SEC2 security-baseline preflight ==="

require_plan "strawwu-security-trust-model.md"

# SEC0: telemetry packages absent from squashfs
telemetry_packages=(apport whoopsie ubuntu-report ubuntu-pro-client snapd)
if has_squashfs; then
    for pkg in "${telemetry_packages[@]}"; do
        if package_installed_in_squashfs "${pkg}"; then
            fail "squashfs still has ${pkg} (W1-B1 purge target — should be absent)"
        else
            pass "squashfs absent ${pkg}"
        fi
    done
else
    warn "squashfs missing — skip telemetry package scan"
fi

if grep -q '預設不上傳' "${PLANS_DIR}/strawwu-security-trust-model.md" \
    || grep -qi 'consent' "${PLANS_DIR}/strawwu-security-trust-model.md"; then
    pass "security plan mentions consent / no auto-upload"
else
    warn "security plan should document bug-report consent"
fi

if [[ -f "${REPO_ROOT}/kernel/config/strawwu.config" ]] || [[ -d "${REPO_ROOT}/kernel" ]]; then
    pass "custom kernel tree present"
else
    warn "kernel tree not found"
fi

# SEC2: bug-reporter privacy filter + consent UI
DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-bug-reporter"
FILTER="${DEB_DIR}/usr/lib/strawwu-bug-reporter/filter.py"
CONSENT="${DEB_DIR}/usr/lib/strawwu-bug-reporter/consent_gtk.py"
UNIT_TEST="${DEB_DIR}/tests/test-privacy-filter.py"

require_file "${FILTER}" "SEC2 filter.py"
require_file "${CONSENT}" "SEC2 consent_gtk.py"
require_file "${UNIT_TEST}" "SEC2 privacy unit test"

for pattern in 'redact_text' 'password' 'token' 'REDACTED'; do
    if grep -q "${pattern}" "${FILTER}"; then
        pass "filter.py contains ${pattern}"
    else
        fail "filter.py missing ${pattern}"
    fi
done

if grep -q 'set_active(False)' "${CONSENT}"; then
    pass "consent UI upload checkbox default off"
else
    fail "consent UI missing default-off upload checkbox"
fi

if grep -q 'upload_opt_in=false' "${DEB_DIR}/debian/postinst"; then
    pass "postinst default upload_opt_in=false"
else
    fail "postinst missing default upload opt-out"
fi

if python3 "${UNIT_TEST}"; then
    pass "SEC2 privacy filter unit tests"
else
    fail "SEC2 privacy filter unit tests"
fi

# Write security-baseline.json
python3 - "${BASELINES_DIR}/security-baseline.json" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
data = {
    "schema": "strawwu-security-baseline/v1",
    "generated_at": "2026-07-05",
    "version": version,
    "telemetry": {
        "default_upload": False,
        "purged_packages": [
            "apport", "whoopsie", "ubuntu-report",
            "ubuntu-pro-client", "snapd",
        ],
        "analytics_daemon": False,
    },
    "bug_reporter": {
        "package": "strawwu-bug-reporter",
        "consent_required": True,
        "auto_upload_default": False,
        "privacy_filter": True,
        "filtered_fields": [
            "password", "token", "secret", "ssh_keys",
            "ssid", "psk", "home_paths",
        ],
    },
    "secure_boot": {
        "enforced": False,
        "documented": True,
    },
    "wave2_gaps": [
        "APT repo Release.gpg + strawwu-keyring (w7-re-apt-repo)",
        "Registry protected list + polkit (SEC3)",
        "compat session audit (SEC4)",
    ],
    "release_signing": {
        "iso": "SHA256SUMS + detached GPG (RE2, w7-re-manifest-gpg)",
        "manifest": "release-manifest.json (RE1)",
        "ci_gpg_secret": "deferred — wire in release.yml",
    },
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline written ${BASELINES_DIR}/security-baseline.json"
validate_json_file "${BASELINES_DIR}/security-baseline.json"

preflight_exit "SEC2 security-baseline"

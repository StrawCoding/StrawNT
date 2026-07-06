#!/usr/bin/env bash
# W7-RE1+RE2: release-manifest generator + GPG signing pipeline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

GEN="${REPO_ROOT}/scripts/generate-release-manifest.sh"
SIGN="${REPO_ROOT}/scripts/release-sign.sh"
VALIDATE="${REPO_ROOT}/tests/release-manifest/validate-release-manifest.py"
BASELINE="${BASELINES_DIR}/release-manifest-baseline.json"
TEST_WORK="${REPO_ROOT}/tests/release-manifest/output"
TEST_OUTPUT="${TEST_WORK}/artifacts"
TEST_VERSION="9.9.9.9"
TEST_ISO="StrawWU-${TEST_VERSION}-amd64.iso"

echo "=== W7-RE manifest+gpg preflight ==="

require_plan "strawwu-release-engineering-plan.md"
require_plan "strawwu-security-trust-model.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${GEN}" "scripts/generate-release-manifest.sh"
require_file "${SIGN}" "scripts/release-sign.sh"
require_file "${VALIDATE}" "tests/release-manifest/validate-release-manifest.py"

for script in "${GEN}" "${SIGN}" "${VALIDATE}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-release-manifest:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-release-manifest target"
else
    fail "Makefile missing test-release-manifest"
fi

if grep -q 'generate-release-manifest' "${REPO_ROOT}/Makefile"; then
    pass "Makefile generate-release-manifest target"
else
    fail "Makefile missing generate-release-manifest"
fi

if grep -q 'release-sign' "${REPO_ROOT}/Makefile"; then
    pass "Makefile release-sign target"
else
    fail "Makefile missing release-sign"
fi

if bash "${SIGN}" --check >/dev/null 2>&1; then
    pass "release-sign --check"
else
    fail "release-sign --check"
fi

# --- isolated artifact test (stub ISO + ephemeral GPG key) ---
rm -rf "${TEST_WORK}"
mkdir -p "${TEST_OUTPUT}"
printf 'strawwu-release-manifest-test-%s\n' "${TEST_VERSION}" > "${TEST_OUTPUT}/${TEST_ISO}"

export GNUPGHOME="${TEST_WORK}/gnupg"
rm -rf "${GNUPGHOME}"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

GPG_BATCH="${GNUPGHOME}/gen-key.batch"
cat > "${GPG_BATCH}" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Name-Real: StrawWU Test Release
Name-Email: release@test.strawwu.local
Expire-Date: 0
%no-protection
%commit
EOF

if gpg --batch --generate-key "${GPG_BATCH}" >/dev/null 2>&1; then
    pass "ephemeral StrawWU GPG test key"
else
    fail "ephemeral GPG key generation"
fi

TEST_KEY="release@test.strawwu.local"
if gpg --list-secret-keys "${TEST_KEY}" >/dev/null 2>&1; then
    pass "ephemeral StrawWU GPG test key (${TEST_KEY})"
else
    fail "ephemeral GPG key not found for ${TEST_KEY}"
fi

export STRAWWU_OUTPUT_DIR="${TEST_OUTPUT}"
export STRAWWU_VERSION="${TEST_VERSION}"
export STRAWWU_RELEASE_CHANNEL="beta"
export STRAWWU_GPG_KEY_ID="${TEST_KEY}"
export STRAWWU_RELEASE_SIGN_MODE="required"

if bash "${SIGN}"; then
    pass "release-sign pipeline (stub ISO)"
else
    fail "release-sign pipeline"
fi

require_file "${TEST_OUTPUT}/SHA256SUMS" "SHA256SUMS"
require_file "${TEST_OUTPUT}/SHA256SUMS.asc" "SHA256SUMS.asc"
require_file "${TEST_OUTPUT}/${TEST_ISO}.asc" "ISO detached signature"
require_file "${TEST_OUTPUT}/release-manifest.json" "release-manifest.json"

if (
    cd "${TEST_OUTPUT}"
    sha256sum -c SHA256SUMS
); then
    pass "sha256sum -c SHA256SUMS"
else
    fail "sha256sum -c SHA256SUMS"
fi

if gpg --verify "${TEST_OUTPUT}/SHA256SUMS.asc" "${TEST_OUTPUT}/SHA256SUMS" >/dev/null 2>&1; then
    pass "gpg --verify SHA256SUMS.asc"
else
    fail "gpg --verify SHA256SUMS.asc"
fi

if python3 "${VALIDATE}" "${TEST_OUTPUT}/release-manifest.json" "${TEST_VERSION}"; then
    pass "validate-release-manifest.py (test artifacts)"
else
    fail "validate-release-manifest.py (test artifacts)"
fi

# --- generate manifest for current VERSION (repo output dir) ---
unset STRAWWU_GPG_KEY_ID
export STRAWWU_OUTPUT_DIR="${REPO_ROOT}/os-image/output"
export STRAWWU_VERSION="${VERSION}"
unset STRAWWU_RELEASE_CHANNEL

if bash "${GEN}"; then
    pass "generate-release-manifest (repo output)"
else
    fail "generate-release-manifest (repo output)"
fi

MANIFEST="${REPO_ROOT}/os-image/output/release-manifest.json"
if [[ -f "${MANIFEST}" ]]; then
    pass "os-image/output/release-manifest.json present"
    if python3 "${VALIDATE}" "${MANIFEST}" "${VERSION}"; then
        pass "validate-release-manifest.py (repo output)"
    else
        fail "validate-release-manifest.py (repo output)"
    fi
else
    fail "release-manifest.json not written to os-image/output"
fi

# --- baseline JSON ---
python3 - "${BASELINE}" "${VERSION}" "${REPO_ROOT}" <<'PY'
import json, sys
from pathlib import Path

out, version, repo = sys.argv[1:4]
repo_path = Path(repo)
data = {
    "schema": "strawwu-release-manifest-baseline/v1",
    "wave": "W7-RE1+RE2",
    "version": version,
    "scripts": {
        "generate_manifest": "scripts/generate-release-manifest.sh",
        "release_sign": "scripts/release-sign.sh",
        "validate": "tests/release-manifest/validate-release-manifest.py",
    },
    "manifest_schema": "strawwu-release-manifest/v1",
    "manifest_path": "os-image/output/release-manifest.json",
    "signing": {
        "checksums": "SHA256SUMS",
        "detached_sig": "SHA256SUMS.asc",
        "iso_sig_suffix": ".asc",
        "modes": ["auto", "required", "skip"],
        "env": ["STRAWWU_GPG_KEY_ID", "STRAWWU_RELEASE_SIGN_MODE"],
    },
    "channels": {
        "beta": {"signed": "sha256+gpg", "preview": True},
        "stable": {"signed": "sha256+gpg", "preview": False},
    },
    "gaps_closed": [
        "release-manifest.json generator (RE1)",
        "SHA256SUMS + GPG release-sign.sh (RE2)",
        "APT publish pipeline (RE4, w7-re-apt-repo)",
        "strawwu-keyring deb (RE3, w7-re-apt-repo)",
    ],
    "deferred": [
        "CI release workflow GPG secret wiring",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline written ${BASELINE}"
validate_json_file "${BASELINE}"

preflight_exit "W7-RE manifest+gpg"

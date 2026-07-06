#!/usr/bin/env bash
# W7-RE3+RE4: APT repo structure + strawwu-keyring + publish-debs pipeline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

PUBLISH="${REPO_ROOT}/scripts/publish-debs.sh"
KEYRING_BUILD="${REPO_ROOT}/os-image/debs/strawwu-keyring/build-deb.sh"
VALIDATE="${REPO_ROOT}/tests/apt-repo/validate-apt-repo.py"
BASELINE="${BASELINES_DIR}/apt-repo-baseline.json"
TEST_WORK="${REPO_ROOT}/tests/apt-repo/output"
TEST_REPO="${TEST_WORK}/apt-repo"
TEST_DEBS="${TEST_WORK}/debs"
TEST_VERSION="9.9.9.9"
TEST_KEY="apt@test.strawwu.local"

echo "=== W7-RE apt-repo preflight ==="

require_plan "strawwu-release-engineering-plan.md"
require_plan "strawwu-security-trust-model.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${PUBLISH}" "scripts/publish-debs.sh"
require_file "${KEYRING_BUILD}" "strawwu-keyring/build-deb.sh"
require_file "${VALIDATE}" "tests/apt-repo/validate-apt-repo.py"
require_file "${REPO_ROOT}/os-image/debs/strawwu-keyring/debian/control" "strawwu-keyring/debian/control"
require_file "${REPO_ROOT}/os-image/debs/strawwu-keyring/keys/strawwu-archive-test.pub" "strawwu-keyring test pubkey"

for script in "${PUBLISH}" "${KEYRING_BUILD}" "${VALIDATE}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'test-apt-repo:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-apt-repo target"
else
    fail "Makefile missing test-apt-repo"
fi

if grep -q 'publish-debs' "${REPO_ROOT}/Makefile"; then
    pass "Makefile publish-debs target"
else
    fail "Makefile missing publish-debs"
fi

if bash "${PUBLISH}" --check >/dev/null 2>&1; then
    pass "publish-debs --check"
else
    fail "publish-debs --check"
fi

if grep -q 'strawwu-archive-keyring.gpg' "${REPO_ROOT}/os-image/config/branding/etc/apt/sources.list.d/strawwu.sources"; then
    pass "branding strawwu.sources Signed-By keyring path"
else
    fail "branding strawwu.sources missing Signed-By keyring"
fi

# --- isolated APT repo test (ephemeral GPG + keyring deb) ---
rm -rf "${TEST_WORK}"
mkdir -p "${TEST_DEBS}"

export GNUPGHOME="${TEST_WORK}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

GPG_BATCH="${GNUPGHOME}/gen-key.batch"
cat > "${GPG_BATCH}" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Name-Real: StrawWU Test Archive
Name-Email: apt@test.strawwu.local
Expire-Date: 0
%no-protection
%commit
EOF

if gpg --batch --generate-key "${GPG_BATCH}" >/dev/null 2>&1; then
    pass "ephemeral StrawWU APT GPG test key"
else
    fail "ephemeral GPG key generation"
fi

KEYRING_GPG="${TEST_WORK}/strawwu-archive-keyring.gpg"
gpg --batch --yes --export "${TEST_KEY}" | gpg --dearmor > "${KEYRING_GPG}"

export STRAWWU_VERSION="${TEST_VERSION}"
export STRAWWU_KEYRING_GPG="${KEYRING_GPG}"
if bash "${KEYRING_BUILD}" >/dev/null 2>&1; then
    pass "strawwu-keyring deb build (test key)"
else
    fail "strawwu-keyring deb build"
fi

KEYRING_DEB="${REPO_ROOT}/os-image/debs/strawwu-keyring/output/strawwu-keyring_${TEST_VERSION}_all.deb"
require_file "${KEYRING_DEB}" "strawwu-keyring test deb"

if dpkg-deb -c "${KEYRING_DEB}" | grep -q 'usr/share/keyrings/strawwu-archive-keyring.gpg'; then
    pass "keyring deb installs strawwu-archive-keyring.gpg"
else
    fail "keyring deb missing archive keyring path"
fi

cp -a "${KEYRING_DEB}" "${TEST_DEBS}/"

export STRAWWU_APT_REPO_DIR="${TEST_REPO}"
export STRAWWU_GPG_KEY_ID="${TEST_KEY}"
export STRAWWU_RELEASE_SIGN_MODE="required"

if bash "${PUBLISH}" --deb-dir "${TEST_DEBS}"; then
    pass "publish-debs pipeline (test deb)"
else
    fail "publish-debs pipeline"
fi

require_file "${TEST_REPO}/dists/resolute/Release" "Release"
require_file "${TEST_REPO}/dists/resolute/Release.gpg" "Release.gpg"
require_file "${TEST_REPO}/dists/resolute/main/binary-amd64/Packages.gz" "Packages.gz"

if python3 "${VALIDATE}" "${TEST_REPO}" resolute amd64 main 1; then
    pass "validate-apt-repo.py (test repo)"
else
    fail "validate-apt-repo.py (test repo)"
fi

if gpg --no-default-keyring --keyring "${KEYRING_GPG}" \
    --verify "${TEST_REPO}/dists/resolute/Release.gpg" "${TEST_REPO}/dists/resolute/Release" >/dev/null 2>&1; then
    pass "gpg --verify Release.gpg with strawwu keyring"
else
    fail "gpg --verify Release.gpg with strawwu keyring"
fi

# --- build keyring for current VERSION (committed test pubkey) ---
unset STRAWWU_KEYRING_GPG STRAWWU_GPG_KEY_ID
export STRAWWU_VERSION="${VERSION}"
if bash "${KEYRING_BUILD}" >/dev/null 2>&1; then
    pass "strawwu-keyring deb build (VERSION=${VERSION})"
else
    fail "strawwu-keyring deb build (VERSION=${VERSION})"
fi

CURRENT_KEYRING_DEB="${REPO_ROOT}/os-image/debs/strawwu-keyring/output/strawwu-keyring_${VERSION}_all.deb"
require_file "${CURRENT_KEYRING_DEB}" "strawwu-keyring current deb"

# --- baseline JSON ---
python3 - "${BASELINE}" "${VERSION}" "${REPO_ROOT}" <<'PY'
import json, sys
from pathlib import Path

out, version, repo = sys.argv[1:4]
repo_path = Path(repo)
data = {
    "schema": "strawwu-apt-repo-baseline/v1",
    "wave": "W7-RE3+RE4",
    "version": version,
    "scripts": {
        "publish_debs": "scripts/publish-debs.sh",
        "keyring_build": "os-image/debs/strawwu-keyring/build-deb.sh",
        "validate": "tests/apt-repo/validate-apt-repo.py",
    },
    "keyring": {
        "package": "strawwu-keyring",
        "path": "/usr/share/keyrings/strawwu-archive-keyring.gpg",
        "sources": "os-image/config/branding/etc/apt/sources.list.d/strawwu.sources",
    },
    "repo_layout": {
        "suite": "resolute",
        "component": "main",
        "arch": "amd64",
        "dists": "dists/{suite}/Release",
        "release_sig": "dists/{suite}/Release.gpg",
        "packages": "dists/{suite}/main/binary-amd64/Packages.gz",
        "pool": "pool/main/{letter}/{package}/",
    },
    "apt_uris": [
        "https://strawcoding.github.io/strawwu-apt",
        "https://apt.strawwu.wastebase.xyz",
    ],
    "gaps_closed": [
        "APT repo dists/ + pool/ structure (RE3)",
        "strawwu-keyring deb (RE3)",
        "publish-debs.sh Release.gpg pipeline (RE4)",
    ],
    "deferred": [
        "production archive signing key deployment",
    ],
}
# Close w7-ci-nightly GPG wiring gap when release workflow is wired
release_yml = repo_path / ".github/workflows/release.yml"
if release_yml.is_file():
    text = release_yml.read_text(encoding="utf-8", errors="replace")
    if "ci-import-gpg.sh" in text and "STRAWWU_GPG_PRIVATE_KEY" in text:
        item = "CI release workflow GPG secret wiring (w7-ci-nightly)"
        if item not in data["gaps_closed"]:
            data["gaps_closed"].append(item)
        data["deferred"] = [x for x in data["deferred"] if "w7-ci-nightly" not in x.lower()]
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline written ${BASELINE}"
validate_json_file "${BASELINE}"

preflight_exit "W7-RE apt-repo"

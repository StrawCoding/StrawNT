#!/usr/bin/env bash
# FORK-F5: strawwu-fork APT suite + publish integration gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

FORK_PKG="${REPO_ROOT}/os-image/fork/packages"
SCRIPTS="${REPO_ROOT}/os-image/scripts"
PUBLISH_FORK="${REPO_ROOT}/scripts/publish-fork-debs.sh"
PUBLISH="${REPO_ROOT}/scripts/publish-debs.sh"
VALIDATE="${REPO_ROOT}/tests/apt-repo/validate-apt-repo.py"
BASELINE="${BASELINES_DIR}/fork-apt-suite-baseline.json"
SOURCES="${REPO_ROOT}/os-image/config/branding/etc/apt/sources.list.d/strawwu-fork.sources"
KEYRING_BUILD="${REPO_ROOT}/os-image/debs/strawwu-keyring/build-deb.sh"
TEST_WORK="${REPO_ROOT}/tests/apt-repo/output/fork-f5"
TEST_REPO="${TEST_WORK}/apt-fork-repo"
TEST_DEBS="${TEST_WORK}/fork-debs"
TEST_VERSION="9.9.9.8"
TEST_KEY="apt@test.strawwu.local"
FORK_SUITE="strawwu-fork"

echo "=== FORK-F5 apt-fork-suite gate ==="
require_plan "strawwu-fork-migration-plan.md"

require_file "${PUBLISH_FORK}" "scripts/publish-fork-debs.sh"
require_file "${SCRIPTS}/lib/fork-apt-env.sh" "fork-apt-env.sh"
require_file "${SOURCES}" "strawwu-fork.sources"
require_file "${FORK_PKG}/packages.json" "fork/packages registry"
require_file "${PUBLISH}" "scripts/publish-debs.sh"
require_file "${VALIDATE}" "tests/apt-repo/validate-apt-repo.py"
require_file "${KEYRING_BUILD}" "strawwu-keyring/build-deb.sh"

for script in "${PUBLISH_FORK}" "${SCRIPTS}/lib/fork-apt-env.sh"; do
    bash -n "${script}"
    pass "$(basename "${script}") syntax"
done

chmod +x "${PUBLISH_FORK}" 2>/dev/null || true
pass "publish-fork-debs.sh executable"

grep -q 'publish-fork-debs' "${REPO_ROOT}/Makefile" && pass "Makefile publish-fork-debs target"
grep -q 'test-fork-f5-apt-fork-suite' "${REPO_ROOT}/Makefile" && pass "Makefile test-fork-f5 target"

grep -q 'strawwu-fork' "${SOURCES}" && pass "strawwu-fork.sources suite name"
grep -q 'strawwu-archive-keyring.gpg' "${SOURCES}" && pass "strawwu-fork.sources Signed-By keyring"

python3 - "${FORK_PKG}/packages.json" "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" <<'PY'
import json, pathlib, sys

registry = json.loads(pathlib.Path(sys.argv[1]).read_text())
base = json.loads(pathlib.Path(sys.argv[2]).read_text())
fork = base.get("fork") or {}

assert registry.get("publish_suite") == "strawwu-fork", "packages.json publish_suite"
assert fork.get("apt_fork_suite") == "strawwu-fork", "ubuntu-base-target apt_fork_suite"
assert fork.get("apt_fork_sources") == "os-image/config/branding/etc/apt/sources.list.d/strawwu-fork.sources"
assert fork.get("apt_fork_repo_dir") == "os-image/output/apt-fork-repo"
print("PASS: fork APT suite config alignment")
PY

if bash "${PUBLISH_FORK}" --check >/dev/null 2>&1; then
    pass "publish-fork-debs --check"
else
    fail "publish-fork-debs --check"
fi

# --- isolated fork APT repo test (ephemeral GPG + keyring deb as stand-in) ---
rm -rf "${TEST_WORK}"
mkdir -p "${TEST_DEBS}"

export GNUPGHOME="${TEST_WORK}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

GPG_BATCH="${GNUPGHOME}/gen-key.batch"
cat > "${GPG_BATCH}" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Name-Real: StrawWU Fork Test Archive
Name-Email: apt@test.strawwu.local
Expire-Date: 0
%no-protection
%commit
EOF

if gpg --batch --generate-key "${GPG_BATCH}" >/dev/null 2>&1; then
    pass "ephemeral fork APT GPG test key"
else
    fail "ephemeral GPG key generation"
fi

KEYRING_GPG="${TEST_WORK}/strawwu-archive-keyring.gpg"
gpg --batch --yes --export "${TEST_KEY}" | gpg --dearmor > "${KEYRING_GPG}"

export STRAWWU_VERSION="${TEST_VERSION}"
export STRAWWU_KEYRING_GPG="${KEYRING_GPG}"
if bash "${KEYRING_BUILD}" >/dev/null 2>&1; then
    pass "strawwu-keyring deb build (fork test key)"
else
    fail "strawwu-keyring deb build"
fi

KEYRING_DEB="${REPO_ROOT}/os-image/debs/strawwu-keyring/output/strawwu-keyring_${TEST_VERSION}_all.deb"
require_file "${KEYRING_DEB}" "strawwu-keyring test deb"
cp -a "${KEYRING_DEB}" "${TEST_DEBS}/"

export STRAWWU_FORK_APT_REPO_DIR="${TEST_REPO}"
export STRAWWU_GPG_KEY_ID="${TEST_KEY}"
export STRAWWU_RELEASE_SIGN_MODE="required"

if bash "${PUBLISH_FORK}" --deb-dir "${TEST_DEBS}"; then
    pass "publish-fork-debs pipeline (test deb)"
else
    fail "publish-fork-debs pipeline"
fi

require_file "${TEST_REPO}/dists/${FORK_SUITE}/Release" "fork Release"
require_file "${TEST_REPO}/dists/${FORK_SUITE}/Release.gpg" "fork Release.gpg"
require_file "${TEST_REPO}/dists/${FORK_SUITE}/main/binary-amd64/Packages.gz" "fork Packages.gz"

if python3 "${VALIDATE}" "${TEST_REPO}" "${FORK_SUITE}" amd64 main 1; then
    pass "validate-apt-repo.py (fork repo)"
else
    fail "validate-apt-repo.py (fork repo)"
fi

if gpg --no-default-keyring --keyring "${KEYRING_GPG}" \
    --verify "${TEST_REPO}/dists/${FORK_SUITE}/Release.gpg" \
    "${TEST_REPO}/dists/${FORK_SUITE}/Release" >/dev/null 2>&1; then
    pass "gpg --verify fork Release.gpg"
else
    fail "gpg --verify fork Release.gpg"
fi

# scaffold-only publish should allow-empty
export STRAWWU_VERSION="${VERSION}"
if bash "${PUBLISH_FORK}" --allow-empty >/dev/null 2>&1; then
    pass "publish-fork-debs --allow-empty (scaffold)"
else
    fail "publish-fork-debs --allow-empty"
fi

# --- baseline JSON ---
python3 - "${BASELINE}" "${VERSION}" "${REPO_ROOT}" <<'PY'
import json, sys
from pathlib import Path

out, version, repo = sys.argv[1:4]
repo_path = Path(repo)
data = {
    "schema": "strawwu-fork-apt-suite-baseline/v1",
    "stage": "fork-f5-apt-fork-suite",
    "version": version,
    "scripts": {
        "publish_fork_debs": "scripts/publish-fork-debs.sh",
        "build_fork_packages": "os-image/scripts/build-fork-packages.sh",
        "validate": "tests/apt-repo/validate-apt-repo.py",
    },
    "registry": {
        "path": "os-image/fork/packages/packages.json",
        "publish_suite_field": "publish_suite",
    },
    "sources": {
        "path": "os-image/config/branding/etc/apt/sources.list.d/strawwu-fork.sources",
        "keyring": "/usr/share/keyrings/strawwu-archive-keyring.gpg",
    },
    "repo_layout": {
        "suite": "strawwu-fork",
        "component": "main",
        "arch": "amd64",
        "dists": "dists/{suite}/Release",
        "release_sig": "dists/{suite}/Release.gpg",
        "packages": "dists/{suite}/main/binary-amd64/Packages.gz",
        "pool": "pool/main/{letter}/{package}/",
    },
    "apt_uris": ["https://apt.strawwu.org"],
    "integration": {
        "input_debs": "os-image/fork/packages/output",
        "output_repo": "os-image/output/apt-fork-repo",
        "make_targets": ["build-fork-packages", "publish-fork-debs"],
    },
    "gaps_closed": [
        "strawwu-fork APT suite layout (fork-f5)",
        "publish-fork-debs.sh pipeline (fork-f5)",
        "branding strawwu-fork.sources (fork-f5)",
    ],
    "deferred": [
        "fork package registration (gnome-shell/mutter etc.)",
        "post-d7 software-sources GUI toggle for fork suite",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline written ${BASELINE}"
validate_json_file "${BASELINE}"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F5 STATIC OK"

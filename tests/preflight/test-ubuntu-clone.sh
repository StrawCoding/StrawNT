#!/usr/bin/env bash
# Preflight: static checks before any ISO clone or E2E.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAIL=0

check() {
    if "$@"; then
        echo "PASS: $*"
    else
        echo "FAIL: $*"
        FAIL=1
    fi
}

echo "=== StrawWU preflight ==="

check test -f "${REPO_ROOT}/docs/architecture.md"
check test -f "${REPO_ROOT}/os-image/scripts/clone-ubuntu-base.sh"
check test -f "${REPO_ROOT}/os-image/scripts/swap-kernel.sh"
check test -f "${REPO_ROOT}/os-image/scripts/build-iso.sh"
check test -x "${REPO_ROOT}/os-image/scripts/clone-ubuntu-base.sh" || chmod +x "${REPO_ROOT}/os-image/scripts/"*.sh

for cmd in unsquashfs xorriso sha256sum; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "PASS: command $cmd"
    else
        echo "WARN: optional command missing: $cmd"
    fi
done

# Ensure we are NOT accidentally using legacy mmdebstrap pipeline
if grep -rq 'mmdebstrap' "${REPO_ROOT}/os-image/scripts/" 2>/dev/null; then
    echo "FAIL: mmdebstrap found in scripts — use Ubuntu clone only"
    FAIL=1
else
    echo "PASS: no mmdebstrap in os-image scripts"
fi

# Branding overlay must not override partition/welcome/settings
for forbidden in partition.conf welcome.conf settings.conf devices.conf; do
    if [[ -f "${REPO_ROOT}/os-image/config/${forbidden}" ]]; then
        echo "FAIL: os-image/config/${forbidden} must not exist (use upstream ubuntu-common)"
        FAIL=1
    fi
done
echo "PASS: no forbidden calamares overrides in config/"

# components/ must not contain copied legacy crates (code artifacts only)
LEGACY_CRATE_DIRS=(strawwu-kernel-bridge strawwu-control-center)
for crate in "${LEGACY_CRATE_DIRS[@]}"; do
    if [[ -d "${REPO_ROOT}/components/${crate}" ]]; then
        echo "FAIL: legacy crate directory components/${crate}/ — v3.0-cleanroom forbids copying legacy code"
        FAIL=1
    fi
done
if [[ "${FAIL}" -eq 0 ]]; then
    echo "PASS: no legacy crate directories in components/"
fi

# Version policy: MAJOR must be 0 until user authorizes official release
STRAWWU_VER="${STRAWWU_VERSION:-$(cat "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.3.0-cleanroom)}"
VER_MAJOR="${STRAWWU_VER%%.*}"
if [[ "${STRAWWU_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+-cleanroom$ ]]; then
    echo "PASS: version policy OK (plan build ${STRAWWU_VER})"
elif [[ "${STRAWWU_OFFICIAL_RELEASE:-0}" != "1" ]] && [[ "${VER_MAJOR}" -ge 1 ]]; then
    echo "FAIL: semver MAJOR=${VER_MAJOR} (version=${STRAWWU_VER}) — pre-release requires MAJOR=0; official release needs user authorization"
    FAIL=1
elif [[ "${STRAWWU_OFFICIAL_RELEASE:-0}" == "1" ]] && [[ ! -f "${REPO_ROOT}/.official-release-authorized" ]]; then
    echo "FAIL: STRAWWU_OFFICIAL_RELEASE=1 but .official-release-authorized marker missing"
    FAIL=1
else
    echo "PASS: version policy OK (${STRAWWU_VER}, major=${VER_MAJOR})"
fi

# No legacy path references inside components/
if grep -rq 'StrawWU-legacy\|封存/StrawWU' "${REPO_ROOT}/components/" 2>/dev/null; then
    echo "FAIL: legacy path reference in components/"
    FAIL=1
else
    echo "PASS: no legacy path references in components/"
fi

echo "=== preflight done ==="
exit "${FAIL}"

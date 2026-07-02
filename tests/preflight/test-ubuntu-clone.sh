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

LEGACY="../封存/StrawWU-legacy-2026-07-02"
if [[ -d "${REPO_ROOT}/${LEGACY}" ]] || [[ -d "/mnt/data/code/project/StrawCoding/封存/StrawWU-legacy-2026-07-02" ]]; then
    echo "PASS: legacy archive present"
else
    echo "WARN: legacy archive dir not found at expected path"
fi

echo "=== preflight done ==="
exit "${FAIL}"

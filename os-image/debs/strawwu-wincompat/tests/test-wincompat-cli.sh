#!/usr/bin/env bash
# Unit checks for strawwu-wincompat CLI contract (host or unpacked deb).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
STRAWWU_BIN="${STRAWWU_BIN:-}"

if [[ -z "${STRAWWU_BIN}" ]]; then
    candidate="${REPO_ROOT}/components/target/release/strawwu"
    if [[ -x "${candidate}" ]]; then
        STRAWWU_BIN="${candidate}"
    else
        echo "FAIL: set STRAWWU_BIN or build components first" >&2
        exit 1
    fi
fi

failures=0
check() {
    local label="$1"
    shift
    if "$@"; then
        echo "PASS: ${label}"
    else
        echo "FAIL: ${label}" >&2
        failures=$((failures + 1))
    fi
}

check "strawwu --version" "${STRAWWU_BIN}" --version
check "strawwu version" "${STRAWWU_BIN}" version
if "${STRAWWU_BIN}" status 2>/dev/null | grep -q 'status'; then
    echo "PASS: strawwu status"
else
    echo "FAIL: strawwu status" >&2
    failures=$((failures + 1))
fi
if "${STRAWWU_BIN}" help 2>/dev/null | grep -q 'USAGE'; then
    echo "PASS: strawwu help"
else
    echo "FAIL: strawwu help" >&2
    failures=$((failures + 1))
fi
if "${STRAWWU_BIN}" not-a-command >/dev/null 2>&1; then
    echo "FAIL: unknown command should fail" >&2
    failures=$((failures + 1))
else
    echo "PASS: strawwu unknown command fails"
fi

baseline="${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml"
check "baseline.yaml exists" test -f "${baseline}"
check "baseline schema" grep -q 'strawwu-wincompat-baseline/v1' "${baseline}"
check "baseline log path" grep -q '/var/log/strawwu/wincompat.log' "${baseline}"

if [[ "${failures}" -eq 0 ]]; then
    echo "=== wincompat CLI tests: PASS (${failures} failures) ==="
    exit 0
fi

echo "=== wincompat CLI tests: FAIL (${failures} failures) ==="
exit 1

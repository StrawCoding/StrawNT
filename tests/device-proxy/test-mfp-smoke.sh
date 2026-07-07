#!/usr/bin/env bash
# POST-Q3 — MFP print+scan smoke (network printer; fixture or live CUPS/SANE).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STRAWWU_BIN="${STRAWWU_BIN:-${REPO_ROOT}/components/target/debug/strawwu}"
FIXTURE="${REPO_ROOT}/os-image/debs/strawwu-device-proxy/usr/share/strawwu/device-proxy/mfp-fixture-catalog.json"

export STRAWWU_MFP_FIXTURE=1
export STRAWWU_MFP_FIXTURE_PATH="${STRAWWU_MFP_FIXTURE_PATH:-${FIXTURE}}"

if [[ ! -x "${STRAWWU_BIN}" ]]; then
    (cd "${REPO_ROOT}/components" && cargo build --bin strawwu -q)
fi

if ! "${STRAWWU_BIN}" mfp smoke >/dev/null; then
    echo "FAIL: strawwu mfp smoke exit non-zero" >&2
    exit 1
fi
echo "PASS: strawwu mfp smoke CLI"

if ! "${STRAWWU_BIN}" mfp smoke --json | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["schema"] == "strawwu-mfp-smoke/v1"
assert data["printer"]["connection"] == "network"
assert data["print"]["status"] == "PASS"
assert data["scan"]["status"] == "PASS"
assert data["aggregate"] == "PASS"
print("PASS: network MFP print+scan aggregate PASS")
'; then
    echo "FAIL: MFP smoke JSON contract" >&2
    exit 1
fi

if ! "${STRAWWU_BIN}" devices list | grep -q $'Printer\t'; then
    echo "FAIL: Printer row missing from devices list" >&2
    exit 1
fi
echo "PASS: Printer device-proxy row present"

echo "=== POST-Q3 MFP smoke: PASS ==="

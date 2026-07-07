#!/usr/bin/env bash
# DDP3 — COM port mapping smoke (uses strawwu devices list + ComPortMapper contract).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STRAWWU_BIN="${STRAWWU_BIN:-${REPO_ROOT}/components/target/debug/strawwu}"

if [[ ! -x "${STRAWWU_BIN}" ]]; then
    (cd "${REPO_ROOT}/components" && cargo build --bin strawwu -q)
fi

if "${STRAWWU_BIN}" devices list | grep -q $'Serial/COM\t'; then
    echo "PASS: COM mapping row in devices list"
else
    echo "FAIL: COM mapping missing from devices list" >&2
    exit 1
fi

if "${STRAWWU_BIN}" devices list --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert any(x.get("class")=="Serial/COM" for x in d["devices"])'; then
    echo "PASS: COM mapping in devices list JSON"
else
    echo "FAIL: COM mapping JSON" >&2
    exit 1
fi

echo "=== DDP3 COM smoke: PASS ==="

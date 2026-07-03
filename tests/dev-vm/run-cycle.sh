#!/usr/bin/env bash
# Full dev-vm cycle: snapshot (optional) → sync → test → rollback on failure.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${STRAWWU_DEV_VM_SAVE_SNAPSHOT:-0}" == "1" ]]; then
    bash "${SCRIPT_DIR}/snapshot-save.sh"
fi

bash "${SCRIPT_DIR}/sync-to-vm.sh"
if bash "${SCRIPT_DIR}/run-test.sh"; then
    echo "PASS: dev-vm cycle"
    exit 0
fi

echo "FAIL: dev-vm cycle — rolling back" >&2
bash "${SCRIPT_DIR}/rollback-snapshot.sh" || true
exit 1

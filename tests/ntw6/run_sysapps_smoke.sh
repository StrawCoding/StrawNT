#!/usr/bin/env bash
# ntw6 dedicated system apps smoke — delegates to tests/strawnt/ntw6-sysapps.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/tests/strawnt/ntw6-sysapps.sh" "$@"

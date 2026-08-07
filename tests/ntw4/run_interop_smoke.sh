#!/usr/bin/env bash
# Plan-path alias → tests/strawnt/ntw4-interop.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "${ROOT}/tests/strawnt/ntw4-interop.sh"

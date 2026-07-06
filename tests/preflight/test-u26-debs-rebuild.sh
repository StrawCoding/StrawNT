#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "${REPO_ROOT}/tests/preflight/lib/u26-stage-stub.sh" "u26-debs-rebuild"

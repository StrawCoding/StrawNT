#!/usr/bin/env bash
# W6-W6: Windows compat E2E smoke — delegates to preflight CLI harness.
# ISO/live Playwright coverage is a separate Hermes gate (release-iso).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "${REPO_ROOT}/tests/preflight/test-wincompat-e2e.sh" "$@"

#!/usr/bin/env bash
# POST-Q3: MFP print+scan smoke gate (network printer).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DDP_DEB="${REPO_ROOT}/os-image/debs/strawwu-device-proxy"
CLI_DIR="${REPO_ROOT}/components/strawwu-cli"
MFP_SMOKE="${REPO_ROOT}/tests/device-proxy/test-mfp-smoke.sh"
BASELINE="${BASELINES_DIR}/mfp-smoke-baseline.json"
FIXTURE="${DDP_DEB}/usr/share/strawwu/device-proxy/mfp-fixture-catalog.json"

echo "=== POST-Q3 MFP smoke preflight ==="
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-Q3-mfp-smoke.md" "kickoff POST-Q3"
require_file "${REPO_ROOT}/components/specs/device-driver-proxy.md" "device-driver-proxy spec"
require_file "${REPO_ROOT}/docs/decisions-2026-07-02.md" "Q3 MFP decision lock"

require_file "${CLI_DIR}/src/mfp.rs" "strawwu-cli mfp.rs"
require_file "${REPO_ROOT}/components/strawwu-device-proxy/src/mfp.rs" "device-proxy mfp.rs"
require_file "${FIXTURE}" "mfp fixture catalog"

if grep -q 'parse_mfp\|MfpSubcommand' "${REPO_ROOT}/components/strawwu-launcher/src/cli.rs"; then
    pass "launcher parses mfp smoke subcommand"
else
    fail "launcher missing mfp smoke subcommand"
fi

MANIFEST="${DDP_DEB}/usr/share/strawwu/device-proxy/device-proxy-manifest.yaml"
if grep -q 'mfp_smoke:' "${MANIFEST}"; then
    pass "device-proxy manifest includes mfp_smoke"
else
    fail "device-proxy manifest missing mfp_smoke"
fi

if grep -q 'test-mfp-smoke' "${REPO_ROOT}/Makefile"; then
    pass "Makefile exposes test-mfp-smoke"
else
    fail "Makefile missing test-mfp-smoke"
fi

if (cd "${REPO_ROOT}/components" && cargo test -p strawwu-device-proxy mfp --quiet); then
    pass "cargo test strawwu-device-proxy mfp"
else
    fail "cargo test strawwu-device-proxy mfp"
fi

if (cd "${REPO_ROOT}/components" && cargo test -p strawwu-cli mfp --quiet); then
    pass "cargo test strawwu-cli mfp"
else
    fail "cargo test strawwu-cli mfp"
fi

if bash "${MFP_SMOKE}"; then
    pass "POST-Q3 MFP device-proxy smoke script"
else
    fail "POST-Q3 MFP device-proxy smoke script"
fi

if python3 "${DDP_DEB}/tests/test-mfp-smoke.py" -q; then
    pass "strawwu-device-proxy mfp python tests"
else
    fail "strawwu-device-proxy mfp python tests"
fi

mkdir -p "${BASELINES_DIR}"
python3 - "${BASELINE}" "${VERSION}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
data = {
    "schema": "strawwu-mfp-smoke-baseline/v1",
    "stage": "post-q3-mfp-smoke",
    "version": version,
    "cli": "strawwu mfp smoke",
    "json_cli": "strawwu mfp smoke --json",
    "fixture": "os-image/debs/strawwu-device-proxy/usr/share/strawwu/device-proxy/mfp-fixture-catalog.json",
    "smoke_script": "tests/device-proxy/test-mfp-smoke.sh",
    "preflight": "tests/preflight/test-mfp-smoke.sh",
    "expect": {
        "network_printers": 1,
        "print": "PASS",
        "scan": "PASS",
        "aggregate": "PASS",
    },
    "dod": "Win app print+scan via CUPS/SANE-IPP mapping; >=1 network MFP PASS (fixture or live)",
}
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {path}")
PY
pass "mfp-smoke baseline"

require_file "${PLANS_DIR}/stage-reports/POST-Q3-mfp-smoke-report.md" "stage report POST-Q3"

preflight_exit "POST-Q3 MFP smoke"

#!/usr/bin/env bash
# W7 PERF1+LEG4: performance size gate + release legal compliance CI wiring.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== W7 PERF+LEGAL gate preflight ==="

require_plan "strawwu-performance-budget-plan.md"
require_plan "strawwu-legal-compliance-plan.md"

CI_YML="${REPO_ROOT}/.github/workflows/ci.yml"
RELEASE_YML="${REPO_ROOT}/.github/workflows/release.yml"
PERF_SCRIPT="${REPO_ROOT}/tests/preflight/test-perf-baseline.sh"
LEGAL_SCRIPT="${REPO_ROOT}/tests/preflight/test-legal-trademark.sh"

for path in "${CI_YML}" "${RELEASE_YML}" "${PERF_SCRIPT}" "${LEGAL_SCRIPT}"; do
    require_file "${path}" "${path#${REPO_ROOT}/}"
done

make_targets=(
    test-perf-baseline
    test-legal-trademark
    test-perf-legal-gate
)
for target in "${make_targets[@]}"; do
    if grep -q "^${target}:" "${REPO_ROOT}/Makefile"; then
        pass "Makefile target ${target}"
    else
        fail "Makefile missing target ${target}"
    fi
done

# --- CI3 PR gate: explicit perf + legal compliance steps ---
ci_checks=(
    'make test-perf-baseline'
    'make test-legal-trademark'
)
for needle in "${ci_checks[@]}"; do
    if grep -qF "${needle}" "${CI_YML}"; then
        pass "ci.yml contains ${needle}"
    else
        fail "ci.yml missing ${needle}"
    fi
done

# --- LEG4 + PERF1 release gate (after ISO build) ---
release_checks=(
    'STRAWWU_PERF_GATE: strict'
    'make test-perf-baseline'
    'make test-legal-trademark'
)
for needle in "${release_checks[@]}"; do
    if grep -qF "${needle}" "${RELEASE_YML}"; then
        pass "release.yml contains ${needle}"
    else
        fail "release.yml missing ${needle}"
    fi
done

# --- isolated PERF1 strict gate (stub ISO under budget) ---
TEST_WORK="${REPO_ROOT}/tests/ci/output/perf-legal"
TEST_OUTPUT="${TEST_WORK}/artifacts"
TEST_VERSION="9.9.9.9"
TEST_ISO="StrawWU-${TEST_VERSION}-amd64.iso"
rm -rf "${TEST_WORK}"
mkdir -p "${TEST_OUTPUT}"
# 64 MiB stub — well under 7 GB budget
truncate -s 67108864 "${TEST_OUTPUT}/${TEST_ISO}"

if STRAWWU_PERF_GATE=strict \
    STRAWWU_OUTPUT_DIR="${TEST_OUTPUT}" \
    bash "${PERF_SCRIPT}" >/dev/null 2>&1; then
    pass "PERF1 strict gate passes with stub ISO under budget"
else
    fail "PERF1 strict gate should pass with stub ISO under budget"
fi

# --- isolated PERF1 strict gate (oversize ISO must fail) ---
OVERSIZE_WORK="${TEST_WORK}/oversize"
mkdir -p "${OVERSIZE_WORK}"
truncate -s 8053063680 "${OVERSIZE_WORK}/StrawWU-oversize-amd64.iso"  # 7.5 GiB
if STRAWWU_PERF_GATE=strict STRAWWU_OUTPUT_DIR="${OVERSIZE_WORK}" bash "${PERF_SCRIPT}" >/dev/null 2>&1; then
    fail "PERF1 strict gate should fail when ISO exceeds 7GB budget"
else
    pass "PERF1 strict gate rejects oversize ISO"
fi
rm -rf "${TEST_WORK}"

# --- refresh perf-baseline.json from repo ISO (undo isolation side effects) ---
bash "${PERF_SCRIPT}" >/dev/null
pass "perf-baseline.json refreshed from repo artifacts"
LEGAL_BASELINE="${BASELINES_DIR}/legal-baseline.json"
python3 - "${LEGAL_BASELINE}" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
path = Path(out)
data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
data.update({
    "schema": "strawwu-legal-baseline/v1",
    "generated_at": "2026-07-06",
    "version": version,
    "phases": {
        "LEG0": {"status": "complete", "artifact": "test-legal-trademark.sh (trademark scan)"},
        "LEG1": {"status": "deferred", "note": "license-inventory.csv auto-generation"},
        "LEG2": {"status": "complete", "artifact": "privacy.html + eula.html"},
        "LEG3": {"status": "deferred", "note": "Calamares/GRUB/Plymouth compliance audit"},
        "LEG4": {
            "status": "complete",
            "workflow": "release.yml + ci.yml",
            "pr_gate": ["test-legal-trademark"],
            "release_gate": ["test-legal-trademark", "test-perf-baseline (strict)"],
        },
    },
})
gaps = [
    "license-inventory.csv auto-generation (LEG1)",
    "Calamares/GRUB/Plymouth compliance audit (LEG3)",
]
data["wave2_gaps"] = gaps
data["gaps_closed"] = data.get("gaps_closed", []) + [
    "release compliance gate CI (LEG4)",
]
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline updated ${LEGAL_BASELINE}"
validate_json_file "${LEGAL_BASELINE}"

# --- update ci-baseline.json with perf/legal gates ---
CI_BASELINE="${BASELINES_DIR}/ci-baseline.json"
if [[ -f "${CI_BASELINE}" ]]; then
    python3 - "${CI_BASELINE}" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))
targets = data.get("make_targets", [])
for t in ("test-perf-baseline", "test-legal-trademark", "test-perf-legal-gate"):
    if t not in targets:
        targets.append(t)
data["make_targets"] = targets
data["version"] = version
data["perf_legal_gates"] = {
    "PERF1": {
        "status": "complete",
        "target": "test-perf-baseline",
        "strict_env": "STRAWWU_PERF_GATE=strict",
        "workflow": "release.yml",
    },
    "LEG4": {
        "status": "complete",
        "target": "test-legal-trademark",
        "workflows": ["ci.yml", "release.yml"],
    },
}
closed = data.get("gaps_closed", [])
for item in (
    "PERF1 ISO size gate in release CI (w7-perf-legal-gate)",
    "LEG4 release compliance gate in CI (w7-perf-legal-gate)",
):
    if item not in closed:
        closed.append(item)
data["gaps_closed"] = closed
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
    pass "ci-baseline.json perf/legal gates recorded"
fi

preflight_exit "W7 PERF+LEGAL gate"

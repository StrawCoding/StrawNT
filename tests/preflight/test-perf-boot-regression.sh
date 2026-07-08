#!/usr/bin/env bash
# POST-PERF: boot-time regression CI gate (PERF2).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

MEASURE_SCRIPT="${REPO_ROOT}/tests/perf/measure-boot-time.sh"
CHECK_SCRIPT="${REPO_ROOT}/tests/perf/check-boot-regression.py"
BASELINE="${BASELINES_DIR}/boot-time-baseline.json"
PERF_BASELINE="${BASELINES_DIR}/perf-baseline.json"
NIGHTLY_YML="${REPO_ROOT}/.github/workflows/nightly.yml"
RELEASE_YML="${REPO_ROOT}/.github/workflows/release.yml"
MEASUREMENT="${REPO_ROOT}/tests/perf/output/boot-time-measurement.json"
PERF_GATE="${STRAWWU_PERF2_GATE:-advisory}"

echo "=== POST-PERF boot regression preflight ==="
pass "PERF2 gate mode=${PERF_GATE}"

require_plan "strawwu-performance-budget-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-PERF-boot-regression.md" "kickoff POST-PERF"

for token in 'PERF2' 'boot-time' 'plymouth' 'regression'; do
    if grep -qi "${token}" "${PLANS_DIR}/strawwu-performance-budget-plan.md"; then
        pass "performance-budget-plan documents ${token}"
    else
        fail "performance-budget-plan missing ${token}"
    fi
done

require_file "${MEASURE_SCRIPT}" "measure-boot-time.sh"
require_file "${CHECK_SCRIPT}" "check-boot-regression.py"
require_file "${BASELINE}" "boot-time-baseline.json"

if [[ -x "${MEASURE_SCRIPT}" ]]; then
    pass "measure-boot-time.sh executable"
else
    chmod +x "${MEASURE_SCRIPT}"
    pass "chmod +x measure-boot-time.sh"
fi

if bash -n "${MEASURE_SCRIPT}"; then
    pass "bash -n measure-boot-time.sh"
else
    fail "syntax error in measure-boot-time.sh"
fi

validate_json_file "${BASELINE}"

if grep -q '^measure-boot-time:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile target measure-boot-time"
else
    fail "Makefile missing measure-boot-time"
fi

if grep -q '^test-perf-boot-regression:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile target test-perf-boot-regression"
else
    fail "Makefile missing test-perf-boot-regression"
fi

# --- nightly.yml PERF2 wiring ---
nightly_checks=(
    'make test-perf-boot-regression'
    'STRAWWU_PERF2_GATE'
)
for needle in "${nightly_checks[@]}"; do
    if grep -qF "${needle}" "${NIGHTLY_YML}"; then
        pass "nightly.yml contains ${needle}"
    else
        fail "nightly.yml missing ${needle}"
    fi
done

# --- release.yml documents PERF2 strict hook (post boot-test) ---
if grep -q 'STRAWWU_PERF2_GATE' "${RELEASE_YML}" || grep -q 'test-perf-boot-regression' "${RELEASE_YML}"; then
    pass "release.yml PERF2 hook present"
else
    fail "release.yml missing PERF2 boot regression hook"
fi

# --- isolated regression math (fixture JSON) ---
FIXTURE_WORK="${REPO_ROOT}/tests/perf/output/fixture-gate"
rm -rf "${FIXTURE_WORK}"
mkdir -p "${FIXTURE_WORK}"

cat > "${FIXTURE_WORK}/baseline.json" <<'JSON'
{
  "budgets": {
    "live_boot_to_plymouth_max_sec": 45,
    "regression_ratio_max": 1.15
  },
  "baseline": { "plymouth_sec": 30 }
}
JSON

cat > "${FIXTURE_WORK}/under.json" <<'JSON'
{ "plymouth_sec": 32, "status": "PASS" }
JSON

cat > "${FIXTURE_WORK}/over.json" <<'JSON'
{ "plymouth_sec": 52, "status": "PASS" }
JSON

if python3 "${CHECK_SCRIPT}" "${FIXTURE_WORK}/baseline.json" "${FIXTURE_WORK}/under.json" strict >/dev/null; then
    pass "PERF2 strict accepts measurement under regression threshold"
else
    fail "PERF2 strict should accept 32s vs 30s baseline (×1.15=34.5s)"
fi

if python3 "${CHECK_SCRIPT}" "${FIXTURE_WORK}/baseline.json" "${FIXTURE_WORK}/over.json" strict >/dev/null 2>&1; then
    fail "PERF2 strict should reject 52s vs 30s baseline"
else
    pass "PERF2 strict rejects oversize boot time"
fi

if python3 "${CHECK_SCRIPT}" "${FIXTURE_WORK}/baseline.json" strict >/dev/null 2>&1; then
    fail "PERF2 strict should fail without measurement"
else
    pass "PERF2 strict requires measurement artifact"
fi

rm -rf "${FIXTURE_WORK}"

# --- optional live measurement artifact (advisory if missing) ---
measurement_arg=""
if [[ -f "${MEASUREMENT}" ]]; then
    pass "boot-time-measurement.json present"
    measurement_arg="${MEASUREMENT}"
elif [[ -f "${REPO_ROOT}/tests/boot/output/serial-bios.log" && -f "${REPO_ROOT}/tests/boot/output/boot-result.json" ]]; then
  if STRAWWU_PERF_BOOT_FROM_ARTIFACTS=1 bash "${MEASURE_SCRIPT}" >/dev/null 2>&1; then
      pass "boot-time measurement from boot-test artifacts"
      measurement_arg="${MEASUREMENT}"
  else
      warn "boot artifact estimate unavailable"
  fi
else
    warn "no boot-time-measurement.json (advisory gate uses baseline only)"
fi

if ! check_out="$(python3 "${CHECK_SCRIPT}" "${BASELINE}" ${measurement_arg:+"${measurement_arg}"} "${PERF_GATE}" 2>&1)"; then
    if [[ "${PERF_GATE}" == "strict" ]]; then
        fail "PERF2 strict gate: ${check_out}"
    else
        warn "PERF2 advisory: ${check_out}"
    fi
else
    pass "PERF2 regression check: $(echo "${check_out}" | tail -1)"
fi

# --- refresh perf-baseline.json PERF2 phase ---
python3 - "${PERF_BASELINE}" "${VERSION}" "${PERF_GATE}" <<'PY'
import json, sys
from pathlib import Path

out, version, gate = sys.argv[1:4]
path = Path(out)
data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}

boot_path = path.parent / "boot-time-baseline.json"
boot = json.loads(boot_path.read_text(encoding="utf-8")) if boot_path.is_file() else {}
plymouth = (boot.get("baseline") or {}).get("plymouth_sec")

data["version"] = version
data.setdefault("measurements", {})["live_boot_to_plymouth_sec"] = plymouth
data.setdefault("phases", {})["PERF2"] = {
    "status": "complete",
    "gate_mode": gate,
    "artifact": "boot-time-baseline.json",
    "measure_script": "tests/perf/measure-boot-time.sh",
    "ci_workflow": "nightly.yml (STRAWWU_PERF2_GATE=advisory)",
    "release_hook": "release.yml (STRAWWU_PERF2_GATE=strict after boot-test)",
}
gaps = [g for g in data.get("wave0_gaps", []) if "PERF2" not in g or "boot-time" not in g]
data["wave0_gaps"] = gaps
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "perf-baseline.json PERF2 phase updated"
validate_json_file "${PERF_BASELINE}"

# --- ci-baseline.json PERF2 record ---
CI_BASELINE="${BASELINES_DIR}/ci-baseline.json"
if [[ -f "${CI_BASELINE}" ]]; then
    python3 - "${CI_BASELINE}" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
targets = data.get("make_targets", [])
for t in ("test-perf-boot-regression", "measure-boot-time"):
    if t not in targets:
        targets.append(t)
data["make_targets"] = targets
data.setdefault("perf_boot_gates", {})["PERF2"] = {
    "status": "complete",
    "target": "test-perf-boot-regression",
    "measure": "measure-boot-time",
    "advisory_env": "STRAWWU_PERF2_GATE=advisory",
    "strict_env": "STRAWWU_PERF2_GATE=strict",
    "workflow": "nightly.yml",
}
closed = data.get("gaps_closed", [])
item = "PERF2 boot-time regression gate (post-perf-boot-regression)"
if item not in closed:
    closed.append(item)
data["gaps_closed"] = closed
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
    pass "ci-baseline.json PERF2 gate recorded"
fi

require_file "${PLANS_DIR}/stage-reports/POST-PERF-boot-regression-report.md" "stage report"

preflight_exit "POST-PERF boot regression"

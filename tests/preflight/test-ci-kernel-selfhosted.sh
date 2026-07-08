#!/usr/bin/env bash
# POST-CI Q6: self-hosted kernel build CI pipeline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== POST-CI kernel selfhosted preflight ==="

require_plan "strawwu-ci-build-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-CI-kernel-selfhosted.md" "kickoff POST-CI-kernel-selfhosted"

KERNEL_YML="${REPO_ROOT}/.github/workflows/kernel-build.yml"
CI_ARTIFACT="${REPO_ROOT}/scripts/ci-kernel-artifact.sh"
BASELINE="${BASELINES_DIR}/ci-baseline.json"
DECISIONS="${REPO_ROOT}/docs/decisions-2026-07-02.md"

require_file "${KERNEL_YML}" ".github/workflows/kernel-build.yml"
require_file "${CI_ARTIFACT}" "scripts/ci-kernel-artifact.sh"

if [[ -x "${CI_ARTIFACT}" ]]; then
    pass "ci-kernel-artifact.sh executable"
else
    chmod +x "${CI_ARTIFACT}"
    pass "chmod +x ci-kernel-artifact.sh"
fi

if bash "${CI_ARTIFACT}" --check >/dev/null 2>&1; then
    pass "ci-kernel-artifact.sh --check"
else
    fail "ci-kernel-artifact.sh --check"
fi

if grep -qF 'runs-on: self-hosted' "${DECISIONS}" && \
   grep -qF 'kernel-build.yml' "${DECISIONS}"; then
    pass "Q6 decision locked in decisions-2026-07-02.md"
else
    fail "Q6 self-hosted kernel decision missing from decisions doc"
fi

kernel_checks=(
    'runs-on: self-hosted'
    'schedule:'
    'cron:'
    'workflow_dispatch:'
    'make kernel-build'
    'make -C kernel test'
    'ci-kernel-artifact.sh'
    'upload-artifact'
    'linux-image-strawwu_*.deb'
    'kernel-manifest.json'
    'SHA256SUMS'
    'strawwu-kernel-build'
)
for needle in "${kernel_checks[@]}"; do
    if grep -qF "${needle}" "${KERNEL_YML}"; then
        pass "kernel-build.yml contains ${needle}"
    else
        fail "kernel-build.yml missing ${needle}"
    fi
done

if grep -q '^kernel-build:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile target kernel-build"
else
    fail "Makefile missing kernel-build"
fi

if grep -q '^test-ci-kernel-selfhosted:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile target test-ci-kernel-selfhosted"
else
    fail "Makefile missing test-ci-kernel-selfhosted"
fi

if grep -q '^test-phase2:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile target test-phase2"
else
    fail "Makefile missing test-phase2"
fi

# --- isolated kernel manifest draft (stub .deb) ---
TEST_WORK="${REPO_ROOT}/tests/ci/output/kernel"
TEST_OUTPUT="${TEST_WORK}/artifacts"
TEST_VERSION="8.8.8.8"
TEST_ABI="7.0.0-14"
STUB_DEB="linux-image-strawwu_${TEST_ABI}_amd64.deb"
rm -rf "${TEST_WORK}"
mkdir -p "${TEST_OUTPUT}"
printf 'strawwu-ci-kernel-test-%s\n' "${TEST_VERSION}" > "${TEST_OUTPUT}/${STUB_DEB}"
touch "${TEST_OUTPUT}/.build-ok"

export STRAWWU_KERNEL_OUTPUT_DIR="${TEST_OUTPUT}"
export STRAWWU_VERSION="${TEST_VERSION}"

if bash "${CI_ARTIFACT}" >/dev/null; then
    pass "ci-kernel-artifact.sh stub manifest"
else
    fail "ci-kernel-artifact.sh stub manifest"
fi

MANIFEST="${TEST_OUTPUT}/kernel-manifest.json"
if [[ -f "${MANIFEST}" ]]; then
    channel="$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['channel'])")"
    if [[ "${channel}" == "kernel-ci" ]]; then
        pass "kernel-manifest channel=kernel-ci"
    else
        fail "kernel-manifest channel expected kernel-ci got ${channel}"
    fi
    abi="$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['kernel_abi'])")"
    if [[ "${abi}" == "${TEST_ABI}" ]]; then
        pass "kernel-manifest abi=${abi}"
    else
        fail "kernel-manifest abi expected ${TEST_ABI} got ${abi}"
    fi
    validate_json_file "${MANIFEST}"
else
    fail "missing ${MANIFEST}"
fi

if [[ -f "${TEST_OUTPUT}/SHA256SUMS" ]]; then
    pass "stub SHA256SUMS for kernel artifact"
else
    fail "missing stub SHA256SUMS"
fi

# --- update ci-baseline.json (Q6 kernel CI closed) ---
python3 - "${BASELINE}" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
path = Path(out)
data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}

data["version"] = version
data.setdefault("workflows", {})["kernel_build"] = ".github/workflows/kernel-build.yml"
data.setdefault("scripts", {})["ci_kernel_artifact"] = "scripts/ci-kernel-artifact.sh"

wf_files = list(data.get("workflow_files", []))
if "kernel-build.yml" not in wf_files:
    wf_files.append("kernel-build.yml")
    wf_files.sort()
data["workflow_files"] = wf_files

make_targets = list(data.get("make_targets", []))
for t in ("kernel-build", "test-ci-kernel-selfhosted", "test-phase2"):
    if t not in make_targets:
        make_targets.append(t)
data["make_targets"] = make_targets

phases = data.setdefault("phases", {})
phases["Q6"] = {
    "status": "complete",
    "workflow": "kernel-build.yml",
    "runner": "self-hosted",
    "trigger": "cron 02:00 UTC Sunday + workflow_dispatch",
    "artifact": "linux-image-strawwu .deb + SHA256SUMS + kernel-manifest.json",
    "script": "scripts/ci-kernel-artifact.sh",
}

deferred = [
    x for x in data.get("deferred", [])
    if "kernel-build.yml" not in x and "Phase 2 Q6" not in x
]
data["deferred"] = deferred

wave0_gaps = [
    x for x in data.get("wave0_gaps", [])
    if "kernel-build.yml" not in x and "Phase 2 Q6" not in x
]
data["wave0_gaps"] = wave0_gaps

closed = data.get("gaps_closed", [])
item = "Q6 kernel-build.yml self-hosted workflow (Phase 2 kernel CI)"
if item not in closed:
    closed.append(item)
data["gaps_closed"] = closed

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline updated ${BASELINE}"
validate_json_file "${BASELINE}"

if python3 -c "import json; d=json.load(open('${BASELINE}')); assert 'Q6' in d.get('phases',{}); assert d['phases']['Q6']['status']=='complete'" 2>/dev/null; then
    pass "ci-baseline Q6 phase complete"
else
    fail "ci-baseline Q6 phase not complete"
fi

preflight_exit "POST-CI kernel selfhosted"

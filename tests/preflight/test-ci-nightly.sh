#!/usr/bin/env bash
# W7-CI2+CI3+CI4: nightly pipeline + PR gate + self-hosted runner wiring.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== W7-CI nightly preflight ==="

require_plan "strawwu-ci-build-plan.md"
require_plan "strawwu-release-engineering-plan.md"

CI_YML="${REPO_ROOT}/.github/workflows/ci.yml"
NIGHTLY_YML="${REPO_ROOT}/.github/workflows/nightly.yml"
RELEASE_YML="${REPO_ROOT}/.github/workflows/release.yml"
GPG_IMPORT="${REPO_ROOT}/scripts/ci-import-gpg.sh"
BASELINE="${BASELINES_DIR}/ci-baseline.json"

for path in "${CI_YML}" "${NIGHTLY_YML}" "${RELEASE_YML}" "${GPG_IMPORT}"; do
    require_file "${path}" "${path#${REPO_ROOT}/}"
done

if [[ -x "${GPG_IMPORT}" ]]; then
    pass "ci-import-gpg.sh executable"
else
    chmod +x "${GPG_IMPORT}"
    pass "chmod +x ci-import-gpg.sh"
fi

if bash "${GPG_IMPORT}" --check >/dev/null 2>&1; then
    pass "ci-import-gpg.sh --check"
else
    fail "ci-import-gpg.sh --check"
fi

# --- CI3 PR gate (ci.yml) ---
ci_checks=(
    'make test-phase0'
    'make preflight'
    'make test-perf-baseline'
    'make test-legal-trademark'
    'make test-wincompat'
    'make validate-calamares-preflight'
    'check-version-bump'
)
for needle in "${ci_checks[@]}"; do
    if grep -qF "${needle}" "${CI_YML}"; then
        pass "ci.yml contains ${needle}"
    else
        fail "ci.yml missing ${needle}"
    fi
done

# --- CI2 nightly pipeline (nightly.yml) ---
nightly_checks=(
    'runs-on: self-hosted'
    'schedule:'
    'cron:'
    'make preflight'
    'make dev-iso'
    'STRAWWU_RELEASE_CHANNEL: nightly'
    'make test-perf-boot-regression'
    'STRAWWU_PERF2_GATE'
    'sha256sum'
    'generate-release-manifest'
    'upload-artifact'
)
for needle in "${nightly_checks[@]}"; do
    if grep -qF "${needle}" "${NIGHTLY_YML}"; then
        pass "nightly.yml contains ${needle}"
    else
        fail "nightly.yml missing ${needle}"
    fi
done

if grep -q 'STRAWWU_RELEASE_SIGN_MODE: skip' "${NIGHTLY_YML}"; then
    pass "nightly.yml SHA256-only signing mode"
else
    fail "nightly.yml must set STRAWWU_RELEASE_SIGN_MODE: skip"
fi

# --- release.yml GPG secret wiring (from w7-re-apt-repo deferred) ---
release_checks=(
    'ci-import-gpg.sh'
    'secrets.STRAWWU_GPG_PRIVATE_KEY'
    'secrets.STRAWWU_GPG_KEY_ID'
    'make release-sign'
    'make generate-release-manifest'
)
for needle in "${release_checks[@]}"; do
    if grep -qF "${needle}" "${RELEASE_YML}"; then
        pass "release.yml contains ${needle}"
    else
        fail "release.yml missing ${needle}"
    fi
done

if grep -q 'runs-on: self-hosted' "${RELEASE_YML}"; then
    pass "release.yml uses self-hosted runner"
else
    fail "release.yml must use self-hosted runner"
fi

# --- isolated nightly manifest draft (stub ISO) ---
TEST_WORK="${REPO_ROOT}/tests/ci/output"
TEST_OUTPUT="${TEST_WORK}/artifacts"
TEST_VERSION="8.8.8.8"
TEST_ISO="StrawWU-${TEST_VERSION}-amd64.iso"
rm -rf "${TEST_WORK}"
mkdir -p "${TEST_OUTPUT}"
printf 'strawwu-ci-nightly-test-%s\n' "${TEST_VERSION}" > "${TEST_OUTPUT}/${TEST_ISO}"

export STRAWWU_OUTPUT_DIR="${TEST_OUTPUT}"
export STRAWWU_VERSION="${TEST_VERSION}"
export STRAWWU_RELEASE_CHANNEL=nightly
export STRAWWU_RELEASE_SIGN_MODE=skip

(
    cd "${TEST_OUTPUT}"
    sha256sum "${TEST_ISO}" > SHA256SUMS
)
pass "stub SHA256SUMS for nightly manifest test"

if STRAWWU_OUTPUT_DIR="${TEST_OUTPUT}" STRAWWU_VERSION="${TEST_VERSION}" \
    STRAWWU_RELEASE_CHANNEL=nightly bash "${REPO_ROOT}/scripts/generate-release-manifest.sh" >/dev/null; then
    pass "generate-release-manifest nightly channel"
else
    fail "generate-release-manifest nightly channel"
fi

MANIFEST="${TEST_OUTPUT}/release-manifest.json"
if [[ -f "${MANIFEST}" ]]; then
    channel="$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['channel'])")"
    if [[ "${channel}" == "nightly" ]]; then
        pass "manifest channel=nightly"
    else
        fail "manifest channel expected nightly got ${channel}"
    fi
    validate_json_file "${MANIFEST}"
else
    fail "missing ${MANIFEST}"
fi

# --- update ci-baseline.json (CI2/CI3/CI4 closed) ---
python3 - "${BASELINE}" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
path = Path(out)
data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
data.update({
    "schema": "strawwu-ci-baseline/v1",
    "wave": "W7-CI2+CI3+CI4",
    "version": version,
    "phases": {
        "CI0": {"status": "complete", "artifact": "ci-baseline.json"},
        "CI1": {"status": "deferred", "note": "rootfs reproducibility hash gate"},
        "CI2": {
            "status": "complete",
            "trigger": "cron 03:00 UTC main",
            "workflow": "nightly.yml",
            "iso_mode": "dev-iso",
            "signed": "sha256",
            "artifact_retention_days": 30,
        },
        "CI3": {
            "status": "complete",
            "workflow": "ci.yml",
            "pr_gate": ["preflight", "test-wincompat", "validate-calamares-preflight", "check-version-bump"],
        },
        "CI4": {
            "status": "complete",
            "runner": "self-hosted",
            "workflows": ["nightly.yml", "release.yml"],
            "gpg_import": "scripts/ci-import-gpg.sh",
            "secrets": ["STRAWWU_GPG_PRIVATE_KEY", "STRAWWU_GPG_KEY_ID", "APT_DISPATCH_TOKEN"],
        },
    },
    "gaps_closed": [
        "CI2 nightly pipeline (cron → dev-iso → SHA256 → manifest draft)",
        "CI3 PR gate (preflight + wincompat + calamares + version bump)",
        "CI4 self-hosted runner wiring (nightly + release + GPG secrets)",
    ],
    "deferred": [
        "CI1 rootfs reproducibility hash gate",
        "production archive signing key deployment on runner",
        "kernel-build.yml self-hosted workflow (Phase 2 Q6)",
    ],
})
data["wave0_gaps"] = data.get("deferred", [])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "baseline updated ${BASELINE}"
validate_json_file "${BASELINE}"

# --- apt-repo baseline: move GPG wiring from deferred to closed ---
APT_BASELINE="${BASELINES_DIR}/apt-repo-baseline.json"
if [[ -f "${APT_BASELINE}" ]]; then
    python3 - "${APT_BASELINE}" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
deferred = [x for x in data.get("deferred", []) if "w7-ci-nightly" not in x.lower()]
data["deferred"] = deferred
closed = data.get("gaps_closed", [])
item = "CI release workflow GPG secret wiring (w7-ci-nightly)"
if item not in closed:
    closed.append(item)
data["gaps_closed"] = closed
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
    pass "apt-repo-baseline.json GPG wiring gap closed"
fi

preflight_exit "W7-CI nightly"

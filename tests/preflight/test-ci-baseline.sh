#!/usr/bin/env bash
# CI0: CI / build pipeline baseline + ci-baseline.json.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== CI0 ci-baseline preflight ==="

require_plan "strawwu-ci-build-plan.md"

make_targets=(
    preflight
    preflight-iso-before-boot
    test-phase0
    test-phase2
    test-wincompat
    validate-calamares-preflight
    build-debs
    bump-version
    test-ci-baseline
    test-ci-nightly
    test-perf-baseline
    test-perf-legal-gate
    dev-iso
    generate-release-manifest
    release-sign
)

for target in "${make_targets[@]}"; do
    if grep -q "^${target}:" "${REPO_ROOT}/Makefile"; then
        pass "Makefile target ${target}"
    else
        fail "Makefile missing target ${target}"
    fi
done

if grep -q 'test-wave0-baseline' "${REPO_ROOT}/Makefile"; then
    pass "Makefile target test-wave0-baseline"
else
    fail "Makefile missing test-wave0-baseline (add in W0)"
fi

workflows_dir="${REPO_ROOT}/.github/workflows"
workflow_files=()
if [[ -d "${workflows_dir}" ]]; then
    shopt -s nullglob
    for wf in "${workflows_dir}"/*.yml "${workflows_dir}"/*.yaml; do
        [[ -f "${wf}" ]] || continue
        workflow_files+=("$(basename "${wf}")")
        pass "CI workflow ${wf#${REPO_ROOT}/}"
    done
    shopt -u nullglob
else
    fail "missing ${workflows_dir}"
fi

require_file "${REPO_ROOT}/scripts/ci-import-gpg.sh" "scripts/ci-import-gpg.sh"

if bash "${REPO_ROOT}/scripts/ci-import-gpg.sh" --check >/dev/null 2>&1; then
    pass "ci-import-gpg.sh --check"
else
    fail "ci-import-gpg.sh --check"
fi

python3 - "${BASELINES_DIR}/ci-baseline.json" "${VERSION}" "${REPO_ROOT}" "${workflows_dir}" <<'PY'
import json, sys
from pathlib import Path

out, version, repo, workflows_dir = sys.argv[1:5]
repo_path = Path(repo)
wf_dir = Path(workflows_dir)
workflows = sorted(p.name for p in wf_dir.glob("*.yml")) + sorted(p.name for p in wf_dir.glob("*.yaml"))

data = {
    "schema": "strawwu-ci-baseline/v1",
    "wave": "W7-CI0",
    "version": version,
    "plan": "docs/plans/strawwu-ci-build-plan.md",
    "workflows": {
        "ci": ".github/workflows/ci.yml",
        "nightly": ".github/workflows/nightly.yml",
        "release": ".github/workflows/release.yml",
    },
    "make_targets": [
        "preflight",
        "dev-iso",
        "release-iso",
        "test-wincompat",
        "validate-calamares-preflight",
        "test-ci-baseline",
        "test-ci-nightly",
        "generate-release-manifest",
        "release-sign",
    ],
    "phases": {
        "CI0": {"status": "complete", "artifact": "ci-baseline.json"},
        "CI1": {"status": "deferred", "note": "rootfs reproducibility hash gate"},
        "CI2": {"status": "pending", "trigger": "cron main", "workflow": "nightly.yml"},
        "CI3": {"status": "pending", "workflow": "ci.yml"},
        "CI4": {"status": "pending", "runner": "self-hosted"},
    },
    "workflow_files": workflows,
    "scripts": {
        "ci_import_gpg": "scripts/ci-import-gpg.sh",
        "release_sign": "scripts/release-sign.sh",
        "manifest_generator": "scripts/generate-release-manifest.sh",
    },
    "wave0_gaps": [
        "CI2 nightly pipeline wiring (w7-ci-nightly)",
        "CI3 PR gate expansion (w7-ci-nightly)",
        "CI4 self-hosted runner PoC documentation",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

pass "baseline written ${BASELINES_DIR}/ci-baseline.json"
validate_json_file "${BASELINES_DIR}/ci-baseline.json"

preflight_exit "CI0 ci-baseline"

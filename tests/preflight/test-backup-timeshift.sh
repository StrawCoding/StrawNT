#!/usr/bin/env bash
# POST-BACKUP: Timeshift / system backup PoC gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

BACKUP_DEB="${REPO_ROOT}/os-image/debs/strawwu-backup"
UNIT_TEST="${BACKUP_DEB}/tests/test-backup.py"
HUB_DIR="${REPO_ROOT}/hub"
BASELINE="${BASELINES_DIR}/backup-timeshift-baseline.json"

echo "=== POST-BACKUP timeshift preflight ==="
require_plan "strawwu-backup-plan.md"
require_file "${PLANS_DIR}/kickoff/POST-BACKUP-timeshift.md" "kickoff POST-BACKUP"
require_file "${BACKUP_DEB}/DEBIAN/control" "strawwu-backup deb"
require_file "${BACKUP_DEB}/usr/bin/strawwu-backup" "strawwu-backup CLI"
require_file "${BACKUP_DEB}/usr/lib/strawwu-backup/core.py" "strawwu-backup core"
require_file "${BACKUP_DEB}/usr/share/strawwu/backup/backup-manifest.yaml" "backup manifest"
require_file "${BACKUP_DEB}/usr/share/strawwu/backup/fixture-catalog.json" "backup fixture"
require_file "${BACKUP_DEB}/build-deb.sh" "strawwu-backup build-deb.sh"
require_file "${UNIT_TEST}" "test-backup.py"
require_file "${HUB_DIR}/src/main/backup-service.js" "hub backup-service"
require_file "${HUB_DIR}/tests/fixtures/backup-catalog.json" "hub backup fixture"
require_file "${PLANS_DIR}/stage-reports/POST-BACKUP-timeshift-report.md" "stage report"

for script in "${BACKUP_DEB}/build-deb.sh" "${BACKUP_DEB}/usr/bin/strawwu-backup"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'strawwu-backup' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes strawwu-backup"
else
    fail "build-os-debs missing strawwu-backup"
fi

TARGET_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
if grep -q 'strawwu-backup' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-backup"
else
    fail "target-manifest missing strawwu-backup"
fi

DESKTOP_CONTROL="${REPO_ROOT}/os-image/debs/strawwu-desktop/debian/control"
if grep -q 'strawwu-backup' "${DESKTOP_CONTROL}"; then
    pass "strawwu-desktop recommends strawwu-backup"
else
    fail "strawwu-desktop missing strawwu-backup"
fi

HUB_MANIFEST="${HUB_DIR}/resources/settings-manifest.json"
if python3 - <<PY
import json
data = json.load(open("${HUB_MANIFEST}"))
assert "backup" in {p["id"] for p in data.get("panels", [])}
assert data.get("backup", {}).get("cli") == "/usr/bin/strawwu-backup"
PY
then
    pass "hub settings manifest backup panel"
else
    fail "hub settings manifest missing backup panel"
fi

if grep -q 'tab-backup' "${HUB_DIR}/src/renderer/index.html"; then
    pass "hub renderer backup tab"
else
    fail "hub renderer missing backup tab"
fi

if grep -q 'schema: strawwu-backup/v1' "${BACKUP_DEB}/usr/share/strawwu/backup/backup-manifest.yaml"; then
    pass "backup manifest schema v1"
else
    fail "backup manifest missing schema"
fi

if grep -q 'upgrade_hook' "${BACKUP_DEB}/usr/share/strawwu/backup/backup-manifest.yaml"; then
    pass "backup manifest upgrade hook"
else
    fail "backup manifest missing upgrade hook"
fi

if grep -q 'timeshift' "${BACKUP_DEB}/usr/share/strawwu/backup/backup-manifest.yaml"; then
    pass "backup manifest timeshift backend"
else
    fail "backup manifest missing timeshift"
fi

if python3 "${UNIT_TEST}"; then
    pass "python3 test-backup.py"
else
    fail "test-backup.py"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_BACKUP_FIXTURE=1
export STRAWWU_BACKUP_FIXTURE_PATH="${BACKUP_DEB}/usr/share/strawwu/backup/fixture-catalog.json"
export STRAWWU_BACKUP_ROOT="${tmp_dir}/backups"

if "${BACKUP_DEB}/usr/bin/strawwu-backup" --json preflight | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"], d'; then
    pass "strawwu-backup preflight --json"
else
    fail "strawwu-backup preflight"
fi

if "${BACKUP_DEB}/usr/bin/strawwu-backup" --json status | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="strawwu-backup-status/v1"'; then
    pass "strawwu-backup status --json"
else
    fail "strawwu-backup status"
fi

if "${BACKUP_DEB}/usr/bin/strawwu-backup" --json list | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d["snapshots"])>=2'; then
    pass "strawwu-backup list --json"
else
    fail "strawwu-backup list"
fi

if "${BACKUP_DEB}/usr/bin/strawwu-backup" --json snapshot create --label preflight | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["backend"]=="rsync"'; then
    pass "strawwu-backup snapshot create"
else
    fail "strawwu-backup snapshot create"
fi

if command -v node >/dev/null 2>&1; then
    if (cd "${HUB_DIR}" && node --test test/backup.test.js); then
        pass "hub backup.test.js"
    else
        fail "hub backup.test.js"
    fi
else
    fail "node not available for hub backup tests"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os
version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-backup-timeshift-baseline/v1",
    "stage": "post-backup-timeshift",
    "version": version,
    "package": "strawwu-backup",
    "hub_panel": "backup",
    "backup_root": "/var/lib/strawwu/backups",
    "upgrade_hook": "strawwu-upgrade snapshot",
    "backends": ["rsync", "btrfs", "timeshift"],
    "cli": "usr/bin/strawwu-backup",
    "manifest": "usr/share/strawwu/backup/backup-manifest.yaml",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "ALL CHECKS PASS"

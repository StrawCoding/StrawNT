#!/usr/bin/env bash
# Per-stage preflight stubs for Ubuntu 26.04 migration (expand when stage starts).
set -euo pipefail
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
STAGE="${1:?stage script name without test- prefix}"

case "${STAGE}" in
  u26-base-clone)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    require_file "${PLANS_DIR}/ubuntu-base-target.json" "ubuntu-base-target"
    PYTHONHASHSEED=0 python3 - "${PLANS_DIR}/ubuntu-base-target.json" "${REPO_ROOT}/os-image/work/.clone-ubuntu-base-ok" \
        "${REPO_ROOT}/os-image/work/rootfs/etc/os-release" <<'PY'
import json, pathlib, sys

target_path, marker_path, os_release_path = map(pathlib.Path, sys.argv[1:4])
target = json.loads(target_path.read_text())
active = target.get("active", {})
codename = active.get("codename", "")
version = active.get("version", "")
if codename != "resolute":
    print(f"FAIL: active.codename expected resolute got {codename!r}", file=sys.stderr)
    sys.exit(1)
if not version.startswith("26.04"):
    print(f"FAIL: active.version expected 26.04.x got {version!r}", file=sys.stderr)
    sys.exit(1)
if not marker_path.is_file():
    print(f"FAIL: clone marker missing ({marker_path})", file=sys.stderr)
    sys.exit(1)
if not os_release_path.is_file():
    print(f"FAIL: rootfs os-release missing ({os_release_path})", file=sys.stderr)
    sys.exit(1)
os_release = os_release_path.read_text()
if "VERSION_CODENAME=resolute" not in os_release and "VERSION_ID=\"26.04" not in os_release:
    print("FAIL: rootfs os-release does not look like Ubuntu 26.04 resolute", file=sys.stderr)
    sys.exit(1)
print(f"PASS: active Ubuntu {version} {codename}")
print(f"PASS: clone marker {marker_path}")
print(f"PASS: rootfs os-release resolute")
PY
    ;;
  u26-kernel-rebase|u26-debs-rebuild|u26-suite-migrate|u26-techrefs-refresh|u26-regression-e2e)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    ;;
  software-sources)
    require_plan "strawwu-d7-software-sources-plan.md"
    ;;
  ux-theme-curation)
    require_plan "strawwu-ux-theme-curation-plan.md"
    ;;
  *)
    echo "unknown stage ${STAGE}" >&2
    exit 1
    ;;
esac

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "PASS: ${STAGE} preflight stub"

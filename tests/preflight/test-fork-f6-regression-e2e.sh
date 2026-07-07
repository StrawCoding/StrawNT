#!/usr/bin/env bash
# FORK-F6: fork base boot + install-firstboot E2E regression gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== FORK-F6 regression-e2e gate ==="
require_plan "strawwu-fork-migration-plan.md"
require_file "${PLANS_DIR}/ubuntu-base-target.json" "ubuntu-base-target"
require_file "${REPO_ROOT}/os-image/fork-base/manifest.json" "fork-base manifest"
require_file "${REPO_ROOT}/tests/fork/write-regression-marker.sh" "fork write-regression-marker"
require_file "${REPO_ROOT}/os-image/work/.fork-sync-base-ok" "fork-sync-base marker"
require_file "${REPO_ROOT}/tests/boot/output/boot-result.json" "boot-result.json"
require_file "${REPO_ROOT}/tests/install-e2e/output/firstboot-e2e-result.json" "firstboot-e2e-result.json"
require_file "${REPO_ROOT}/os-image/work/.fork-regression-e2e-ok" "fork-regression-e2e marker"

bash -n "${REPO_ROOT}/tests/fork/write-regression-marker.sh"
pass "write-regression-marker.sh syntax"

PYTHONHASHSEED=0 python3 - \
    "${PLANS_DIR}/ubuntu-base-target.json" \
    "${REPO_ROOT}/os-image/fork-base/manifest.json" \
    "${REPO_ROOT}/VERSION" \
    "${REPO_ROOT}/tests/boot/output/boot-result.json" \
    "${REPO_ROOT}/tests/install-e2e/output/firstboot-e2e-result.json" \
    "${REPO_ROOT}/os-image/output" \
    "${REPO_ROOT}/os-image/work/.fork-sync-base-ok" \
    "${REPO_ROOT}/os-image/work/.fork-regression-e2e-ok" \
    "${REPO_ROOT}/os-image/work/rootfs/etc/os-release" <<'PY'
import json, pathlib, sys

(
    target_path,
    manifest_path,
    version_path,
    boot_path,
    firstboot_path,
    iso_dir,
    fork_sync_path,
    marker_path,
    os_release_path,
) = map(pathlib.Path, sys.argv[1:10])

target = json.loads(target_path.read_text(encoding="utf-8"))
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
active = target.get("active", {})
version = version_path.read_text().strip()
boot = json.loads(boot_path.read_text(encoding="utf-8"))
firstboot = json.loads(firstboot_path.read_text(encoding="utf-8"))
marker = marker_path.read_text().strip().split()

ubuntu = manifest.get("ubuntu", {})
if ubuntu.get("codename") != "resolute":
    print(f"FAIL: manifest ubuntu.codename expected resolute got {ubuntu.get('codename')!r}", file=sys.stderr)
    sys.exit(1)

if active.get("codename") != "resolute":
    print(f"FAIL: active.codename expected resolute got {active.get('codename')!r}", file=sys.stderr)
    sys.exit(1)

if not version.startswith("0.6"):
    print(f"FAIL: VERSION {version!r} not in 0.6.x preview range", file=sys.stderr)
    sys.exit(1)

if not fork_sync_path.is_file():
    print(f"FAIL: fork-sync-base marker missing ({fork_sync_path})", file=sys.stderr)
    sys.exit(1)

iso = iso_dir / f"StrawWU-{version}-amd64.iso"
if not iso.is_file():
    print(f"FAIL: release ISO missing ({iso})", file=sys.stderr)
    sys.exit(1)

if boot.get("version") != version:
    print(f"FAIL: boot-result version {boot.get('version')!r} != VERSION {version!r}", file=sys.stderr)
    sys.exit(1)
if boot.get("status") != "PASS":
    print(f"FAIL: boot-result status {boot.get('status')!r}", file=sys.stderr)
    sys.exit(1)
if boot.get("marker") != "STRAWWU_BOOT_OK":
    print(f"FAIL: boot marker expected STRAWWU_BOOT_OK got {boot.get('marker')!r}", file=sys.stderr)
    sys.exit(1)
for mode in ("bios", "uefi"):
    sub = boot.get(mode, {})
    if sub.get("status") != "PASS":
        print(f"FAIL: boot {mode} status {sub.get('status')!r}", file=sys.stderr)
        sys.exit(1)
    boot_iso = sub.get("iso", "")
    if version not in boot_iso:
        print(f"FAIL: boot {mode} iso {boot_iso!r} does not match VERSION", file=sys.stderr)
        sys.exit(1)

if firstboot.get("version") != version:
    print(f"FAIL: firstboot-e2e version {firstboot.get('version')!r} != VERSION {version!r}", file=sys.stderr)
    sys.exit(1)
if firstboot.get("status") != "PASS":
    print(f"FAIL: firstboot-e2e status {firstboot.get('status')!r}", file=sys.stderr)
    sys.exit(1)
if not firstboot.get("firstboot_ok"):
    print("FAIL: firstboot_ok not true", file=sys.stderr)
    sys.exit(1)
if firstboot.get("firstboot_marker") != "FIRSTBOOT_OK":
    print(f"FAIL: firstboot marker expected FIRSTBOOT_OK got {firstboot.get('firstboot_marker')!r}", file=sys.stderr)
    sys.exit(1)
if not firstboot.get("install_ok") or not firstboot.get("boot_ok"):
    print("FAIL: install_ok or boot_ok not true in firstboot-e2e-result", file=sys.stderr)
    sys.exit(1)

if not marker or marker[0] != "fork":
    print(f"FAIL: .fork-regression-e2e-ok expected fork marker got {marker!r}", file=sys.stderr)
    sys.exit(1)
if len(marker) < 3 or marker[1] != "resolute":
    print(f"FAIL: .fork-regression-e2e-ok suite {marker!r} != fork resolute", file=sys.stderr)
    sys.exit(1)
if marker[2] != version:
    print(f"FAIL: .fork-regression-e2e-ok version {marker[2:]!r} != VERSION {version!r}", file=sys.stderr)
    sys.exit(1)

os_release = os_release_path.read_text(encoding="utf-8") if os_release_path.is_file() else ""
if "VERSION_CODENAME=resolute" not in os_release:
    print("FAIL: rootfs os-release not resolute", file=sys.stderr)
    sys.exit(1)

print(f"PASS: fork manifest Ubuntu {ubuntu.get('version')} resolute")
print(f"PASS: fork-sync-base marker present")
print(f"PASS: release ISO StrawWU-{version}-amd64.iso ({iso.stat().st_size // (1024*1024)} MiB)")
print(f"PASS: boot-result {version} BIOS+UEFI STRAWWU_BOOT_OK")
print(f"PASS: firstboot-e2e {version} install+boot+FIRSTBOOT_OK")
print(f"PASS: .fork-regression-e2e-ok fork resolute {version}")
PY

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    exit 1
fi
echo "FORK-F6 REGRESSION E2E OK"

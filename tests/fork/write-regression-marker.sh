#!/usr/bin/env bash
# Write .fork-regression-e2e-ok after boot-test + install-firstboot E2E PASS on fork base.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
MARKER="${REPO_ROOT}/os-image/work/.fork-regression-e2e-ok"
FORK_MARKER="${REPO_ROOT}/os-image/work/.fork-sync-base-ok"
BOOT="${REPO_ROOT}/tests/boot/output/boot-result.json"
FIRSTBOOT="${REPO_ROOT}/tests/install-e2e/output/firstboot-e2e-result.json"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "${FORK_MARKER}" ]] || die "missing ${FORK_MARKER} (run make fork-sync-base)"
[[ -f "${BOOT}" ]] || die "missing ${BOOT} (run make boot-test-release-iso)"
[[ -f "${FIRSTBOOT}" ]] || die "missing ${FIRSTBOOT} (run make test-install-firstboot-e2e)"

python3 - "${BOOT}" "${FIRSTBOOT}" "${VERSION}" <<'PY'
import json, pathlib, sys

boot_path, firstboot_path, version = sys.argv[1:4]
boot = json.loads(pathlib.Path(boot_path).read_text())
fb = json.loads(pathlib.Path(firstboot_path).read_text())

if boot.get("version") != version or boot.get("status") != "PASS":
    raise SystemExit(f"boot-result not PASS for {version}")
if boot.get("marker") != "STRAWWU_BOOT_OK":
    raise SystemExit("boot marker not STRAWWU_BOOT_OK")
for mode in ("bios", "uefi"):
    sub = boot.get(mode, {})
    if sub.get("status") != "PASS":
        raise SystemExit(f"boot {mode} not PASS")

if fb.get("version") != version or fb.get("status") != "PASS":
    raise SystemExit(f"firstboot-e2e-result not PASS for {version}")
if fb.get("firstboot_marker") != "FIRSTBOOT_OK":
    raise SystemExit("firstboot marker not FIRSTBOOT_OK")
if not fb.get("install_ok") or not fb.get("boot_ok") or not fb.get("firstboot_ok"):
    raise SystemExit("install_ok/boot_ok/firstboot_ok not all true")
PY

printf 'fork resolute %s %s\n' "${VERSION}" "$(date -Is)" > "${MARKER}"
echo "Wrote ${MARKER}"

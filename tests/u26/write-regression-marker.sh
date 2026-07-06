#!/usr/bin/env bash
# Write .regression-e2e-ok after boot-test + install-firstboot E2E PASS on resolute base.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
MARKER="${REPO_ROOT}/os-image/work/.regression-e2e-ok"
BOOT="${REPO_ROOT}/tests/boot/output/boot-result.json"
FIRSTBOOT="${REPO_ROOT}/tests/install-e2e/output/firstboot-e2e-result.json"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "${BOOT}" ]] || die "missing ${BOOT} (run make boot-test-release-iso)"
[[ -f "${FIRSTBOOT}" ]] || die "missing ${FIRSTBOOT} (run make test-install-firstboot-e2e)"

python3 - "${BOOT}" "${FIRSTBOOT}" "${VERSION}" <<'PY'
import json, pathlib, sys

boot_path, firstboot_path, version = sys.argv[1:4]
boot = json.loads(pathlib.Path(boot_path).read_text())
fb = json.loads(pathlib.Path(firstboot_path).read_text())

if boot.get("version") != version or boot.get("status") != "PASS":
    raise SystemExit(f"boot-result not PASS for {version}")
if fb.get("version") != version or fb.get("status") != "PASS":
    raise SystemExit(f"firstboot-e2e-result not PASS for {version}")
if fb.get("firstboot_marker") != "FIRSTBOOT_OK":
    raise SystemExit("firstboot marker not FIRSTBOOT_OK")
PY

printf 'resolute %s %s\n' "${VERSION}" "$(date -Is)" > "${MARKER}"
echo "Wrote ${MARKER}"

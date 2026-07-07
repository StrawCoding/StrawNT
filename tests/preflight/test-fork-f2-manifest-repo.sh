#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"
PKG_DIR="${REPO_ROOT}/os-image/fork-base/packages"
FORK_BASE="${REPO_ROOT}/os-image/fork-base"

echo "=== FORK-F2 manifest-repo gate ==="
for f in include.txt remove.txt replace.json pins.txt; do
    require_file "${PKG_DIR}/${f}" "packages/${f}"
done

bash -n "${REPO_ROOT}/os-image/scripts/fork-apply-manifest.sh"
pass "fork-apply-manifest.sh syntax"

grep -q 'apply_replace' "${REPO_ROOT}/os-image/scripts/fork-apply-manifest.sh" \
    && pass "fork-apply-manifest apply_replace"
grep -q 'apply_pins' "${REPO_ROOT}/os-image/scripts/fork-apply-manifest.sh" \
    && pass "fork-apply-manifest apply_pins"

require_file "${FORK_BASE}/overrides/etc/apt/preferences.d/strawwu-nosnap" "nosnap apt override"

python3 - "${PKG_DIR}" "${FORK_BASE}/manifest.json" <<'PY'
import json, pathlib, sys

pkg_dir = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])

replace = json.loads((pkg_dir / "replace.json").read_text())
assert replace.get("schema") == "strawwu-fork-replace/v1", "replace.json schema"
repl = replace.get("replacements") or {}
required_replacements = {
    "ubuntu-minimal": "strawwu-minimal",
    "ubuntu-desktop": "strawwu-desktop",
    "calamares-settings-ubuntu-common": "strawwu-calamares-settings",
}
for ubuntu_pkg, strawwu_pkg in required_replacements.items():
    assert repl.get(ubuntu_pkg) == strawwu_pkg, f"missing replace {ubuntu_pkg} → {strawwu_pkg}"
print("PASS: replace.json schema + required mappings")

remove = {
    line.split("#", 1)[0].strip()
    for line in (pkg_dir / "remove.txt").read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
}
required_remove = {"snapd", "apport", "ubuntu-desktop"}
missing = required_remove - remove
assert not missing, f"remove.txt missing: {sorted(missing)}"
print(f"PASS: remove.txt curated ({len(remove)} packages)")

include = {
    line.split("#", 1)[0].strip()
    for line in (pkg_dir / "include.txt").read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
}
assert "linux-firmware" in include, "include.txt missing linux-firmware"
assert "flatpak" in include, "include.txt missing flatpak"
print(f"PASS: include.txt curated ({len(include)} packages)")

pins = (pkg_dir / "pins.txt").read_text()
assert "Pin-Priority: 1001" in pins, "pins.txt missing StrawWU priority"
assert "Pin-Priority: -1" in pins, "pins.txt missing nosnap block"
print("PASS: pins.txt apt preferences")

manifest = json.loads(manifest_path.read_text())
assert manifest.get("schema") == "strawwu-fork-base/v1", "manifest schema"
pkgs = manifest.get("packages") or {}
for key in ("include", "remove", "replace", "pins"):
    rel = pkgs.get(key)
    assert rel, f"manifest.packages.{key} missing"
    assert (pathlib.Path(manifest_path).parent / rel).is_file(), f"manifest path missing: {rel}"
print("PASS: manifest.json package references")
PY

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then exit 1; fi
echo "FORK-F2 STATIC OK"

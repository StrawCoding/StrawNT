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
  u26-kernel-rebase)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    require_file "${REPO_ROOT}/kernel/output/.build-ok" "kernel build marker"
    PYTHONHASHSEED=0 python3 - \
        "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" \
        "${REPO_ROOT}/kernel/output" \
        "${REPO_ROOT}/os-image/work/rootfs" <<'PY'
import json, pathlib, re, subprocess, sys

target_path, kernel_out, rootfs = map(pathlib.Path, sys.argv[1:4])
target = json.loads(target_path.read_text())
active = target.get("active", {})
upstream = active.get("kernel_upstream", "6.14")
localver = active.get("kernel_localversion", "-strawwu")

debs = sorted(kernel_out.glob("linux-image-strawwu_*.deb"))
if not debs:
    print("FAIL: linux-image-strawwu_*.deb missing", file=sys.stderr)
    sys.exit(1)
deb = debs[-1]
ver = deb.name.replace("linux-image-strawwu_", "").replace("_amd64.deb", "")
# Resolute ships linux 7.0.0 (upstream 6.14+); reject noble 6.8 artifacts.
if ver.startswith("6.8") or ver.startswith("6.8."):
    print(f"FAIL: kernel deb still noble ABI ({ver})", file=sys.stderr)
    sys.exit(1)
major = int(ver.split(".", 1)[0])
if major < 7:
    print(f"FAIL: kernel deb version {ver} < 7.0 (expected resolute 6.14+ / 7.0.0)", file=sys.stderr)
    sys.exit(1)

abi_file = kernel_out / ".kernel-abi"
if abi_file.is_file():
    abi = abi_file.read_text().strip()
    print(f"PASS: kernel ABI stamp {abi}")

proc = subprocess.run(
    ["dpkg-deb", "-c", str(deb)],
    capture_output=True, text=True, check=True,
)
listing = proc.stdout
if localver not in listing and f"modules/{ver.split('-')[0]}" not in listing:
  # modules dir uses full kver e.g. 7.0.0-14-strawwu
    if not re.search(rf"lib/modules/[0-9].*{re.escape(localver)}", listing):
        print(f"FAIL: {deb.name} missing LOCALVERSION {localver!r} in modules tree", file=sys.stderr)
        sys.exit(1)
if "strawwu_ipc.ko" not in listing:
    print(f"FAIL: strawwu_ipc.ko not in {deb.name}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: linux-image-strawwu deb {deb.name}")
print(f"PASS: upstream target {upstream}+ (deb {ver})")
print(f"PASS: LOCALVERSION {localver} + strawwu_ipc.ko in deb")

# rootfs should reflect swap or still have resolute generic until swap-kernel
rootfs_boot = rootfs / "boot"
if rootfs_boot.is_dir():
    strawwu_vmlinuz = list(rootfs_boot.glob("vmlinuz-*strawwu*"))
    if strawwu_vmlinuz:
        print(f"PASS: rootfs vmlinuz {strawwu_vmlinuz[0].name}")
    else:
        print("WARN: rootfs not yet swapped to strawwu kernel (run make swap-kernel)")
PY
    ;;
  u26-debs-rebuild)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    require_file "${REPO_ROOT}/os-image/scripts/build-os-debs.sh" "build-os-debs.sh"
    require_file "${PLANS_DIR}/ubuntu-base-target.json" "ubuntu-base-target"
    require_file "${REPO_ROOT}/os-image/work/.debs-rebuild-ok" "debs-rebuild marker"
    PYTHONHASHSEED=0 python3 - \
        "${PLANS_DIR}/ubuntu-base-target.json" \
        "${REPO_ROOT}/VERSION" \
        "${REPO_ROOT}/os-image/work/.debs-rebuild-ok" \
        "${REPO_ROOT}/os-image/debs/strawwu-minimal/usr/share/strawwu/meta-audit/meta-audit-manifest.yaml" \
        "${REPO_ROOT}/os-image/debs" \
        "${REPO_ROOT}/os-image/work/rootfs" <<'PY'
import json, pathlib, re, subprocess, sys

target_path, version_path, marker_path, manifest_path, debs_root, rootfs = map(
    pathlib.Path, sys.argv[1:7]
)
target = json.loads(target_path.read_text())
active = target.get("active", {})
if active.get("codename") != "resolute":
    print(f"FAIL: active.codename expected resolute got {active.get('codename')!r}", file=sys.stderr)
    sys.exit(1)

version = version_path.read_text().strip()
marker_ver = marker_path.read_text().strip()
if marker_ver != version:
    print(f"FAIL: .debs-rebuild-ok version {marker_ver!r} != VERSION {version!r}", file=sys.stderr)
    sys.exit(1)

manifest = manifest_path.read_text(encoding="utf-8")
if "ubuntu-wallpapers-noble" in manifest:
    print("FAIL: meta-audit still references ubuntu-wallpapers-noble", file=sys.stderr)
    sys.exit(1)
if "ubuntu-wallpapers-resolute" not in manifest:
    print("FAIL: meta-audit missing ubuntu-wallpapers-resolute allowlist entry", file=sys.stderr)
    sys.exit(1)

amd64_pkgs = {"strawwu-desktop", "strawwu-minimal", "strawwu-wincompat"}
missing = []
for pkg_dir in sorted(debs_root.iterdir()):
    if not pkg_dir.is_dir() or not pkg_dir.name.startswith("strawwu-"):
        continue
    build = pkg_dir / "build-deb.sh"
    if not build.is_file():
        continue
    arch = "amd64" if pkg_dir.name in amd64_pkgs else "all"
    deb = pkg_dir / "output" / f"{pkg_dir.name}_{version}_{arch}.deb"
    if not deb.is_file():
        missing.append(str(deb.relative_to(debs_root.parent.parent)))
if missing:
    print("FAIL: missing rebuilt debs:", file=sys.stderr)
    for m in missing:
        print(f"  {m}", file=sys.stderr)
    sys.exit(1)

proc = subprocess.run(
    ["chroot", str(rootfs), "dpkg", "--audit"],
    capture_output=True, text=True,
)
audit = (proc.stdout + proc.stderr).strip()
if audit:
    print(f"FAIL: rootfs dpkg --audit not clean:\n{audit}", file=sys.stderr)
    sys.exit(1)

proc = subprocess.run(
    ["chroot", str(rootfs), "dpkg-query", "-W", "-f=${Package} ${Version}\n", "strawwu-*"],
    capture_output=True, text=True,
)
installed = []
for ln in proc.stdout.splitlines():
    parts = ln.split()
    if len(parts) >= 2 and parts[1][0].isdigit():
        installed.append(ln)
stale = [ln for ln in installed if not ln.endswith(f" {version}")]
if stale:
    print("FAIL: rootfs strawwu-* not at VERSION:", file=sys.stderr)
    for ln in stale[:10]:
        print(f"  {ln}", file=sys.stderr)
    sys.exit(1)

deb_count = sum(1 for d in debs_root.iterdir() if d.is_dir() and (d / "build-deb.sh").is_file())
print(f"PASS: active Ubuntu {active.get('version')} resolute")
print(f"PASS: .debs-rebuild-ok v{version}")
print(f"PASS: meta-audit allowlist resolute (no noble wallpapers)")
print(f"PASS: {deb_count} strawwu-* debs rebuilt at v{version}")
print(f"PASS: rootfs {len(installed)} strawwu-* packages at v{version}")
print(f"PASS: rootfs dpkg --audit clean")
PY
    ;;
  u26-suite-migrate)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    require_file "${REPO_ROOT}/scripts/publish-debs.sh" "publish-debs.sh"
    require_file "${BASELINES_DIR}/apt-repo-baseline.json" "apt-repo-baseline"
    require_file "${REPO_ROOT}/os-image/config/branding/etc/apt/sources.list.d/strawwu.sources" "strawwu.sources"
    PYTHONHASHSEED=0 python3 - \
        "${REPO_ROOT}/scripts/publish-debs.sh" \
        "${BASELINES_DIR}/apt-repo-baseline.json" \
        "${REPO_ROOT}/os-image/config/branding/etc/apt/sources.list.d/strawwu.sources" \
        "${PLANS_DIR}/ubuntu-base-target.json" <<'PY'
import json, pathlib, re, sys

publish, baseline_path, sources_path, target_path = map(pathlib.Path, sys.argv[1:5])

target = json.loads(target_path.read_text())
active = target.get("active", {})
if active.get("codename") != "resolute":
    print(f"FAIL: active.codename expected resolute got {active.get('codename')!r}", file=sys.stderr)
    sys.exit(1)

baseline = json.loads(baseline_path.read_text())
suite = baseline.get("repo_layout", {}).get("suite", "")
if suite != "resolute":
    print(f"FAIL: apt-repo-baseline suite expected resolute got {suite!r}", file=sys.stderr)
    sys.exit(1)

sources = sources_path.read_text(encoding="utf-8")
if re.search(r"Suites:\s*noble\b", sources):
    print("FAIL: strawwu.sources still uses noble suite", file=sys.stderr)
    sys.exit(1)
if "Suites: resolute" not in sources:
    print("FAIL: strawwu.sources missing Suites: resolute", file=sys.stderr)
    sys.exit(1)

pub = publish.read_text(encoding="utf-8")
if re.search(r"STRAWWU_APT_SUITE:-noble", pub):
    print("FAIL: publish-debs.sh still hard-defaults noble", file=sys.stderr)
    sys.exit(1)
if "load_ubuntu_base_env" not in pub:
    print("FAIL: publish-debs.sh does not load ubuntu-base-env for suite", file=sys.stderr)
    sys.exit(1)

print(f"PASS: active Ubuntu {active.get('version')} resolute")
print("PASS: apt-repo-baseline suite resolute")
print("PASS: strawwu.sources Suites: resolute")
print("PASS: publish-debs.sh derives APT suite from ubuntu-base-target.json")
PY
    ;;
  u26-techrefs-refresh)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    require_file "${REPO_ROOT}/docs/technical-references/scripts/refresh-technical-references.sh" "refresh-technical-references.sh"
    require_file "${REPO_ROOT}/docs/technical-references/indexes/catalog.json" "catalog.json"
    require_file "${REPO_ROOT}/docs/technical-references/.techrefs-refresh-ok" "techrefs-refresh marker"
    PYTHONHASHSEED=0 python3 - \
        "${REPO_ROOT}/docs/technical-references/indexes/catalog.json" \
        "${REPO_ROOT}/docs/technical-references/scripts/refresh-technical-references.sh" \
        "${REPO_ROOT}/docs/technical-references/.techrefs-refresh-ok" \
        "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" \
        "${REPO_ROOT}/VERSION" <<'PY'
import json, pathlib, re, sys

catalog_path, script_path, marker_path, target_path, version_path = map(pathlib.Path, sys.argv[1:6])
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
target = json.loads(target_path.read_text(encoding="utf-8"))
active = target.get("active", {})
version = version_path.read_text().strip()

if catalog.get("ubuntu_release") != "resolute":
    print(f"FAIL: catalog ubuntu_release expected resolute got {catalog.get('ubuntu_release')!r}", file=sys.stderr)
    sys.exit(1)

script = script_path.read_text(encoding="utf-8")
script_code = "\n".join(
    ln for ln in script.splitlines() if not ln.lstrip().startswith("#")
)
if re.search(r"manpages/noble/", script_code):
    print("FAIL: refresh script still references noble manpages", file=sys.stderr)
    sys.exit(1)
if "manpages/${APT_SUITE}/" not in script and "manpages/resolute/" not in script:
    print("FAIL: refresh script missing resolute manpage URLs", file=sys.stderr)
    sys.exit(1)
if re.search(r'\bnoble\b', script_code):
    print("FAIL: refresh script still hardcodes noble", file=sys.stderr)
    sys.exit(1)

marker = marker_path.read_text().strip().split()
if not marker or marker[0] != "resolute":
    print(f"FAIL: .techrefs-refresh-ok expected resolute marker got {marker!r}", file=sys.stderr)
    sys.exit(1)

pkgs = {p["name"]: p for p in catalog.get("packages", [])}
required = ("casper", "initramfs-tools", "calamares", "grub2", "linux-stable")
missing = [n for n in required if n not in pkgs]
if missing:
    print(f"FAIL: catalog missing packages: {missing}", file=sys.stderr)
    sys.exit(1)

linux = pkgs["linux-stable"]
if linux.get("version", "").startswith("v6.8"):
    print(f"FAIL: catalog linux-stable still noble era ({linux.get('version')})", file=sys.stderr)
    sys.exit(1)

if active.get("codename") != "resolute":
    print(f"FAIL: active.codename expected resolute got {active.get('codename')!r}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: catalog ubuntu_release resolute ({len(catalog.get('packages', []))} packages)")
print(f"PASS: refresh script targets resolute manpages")
print(f"PASS: .techrefs-refresh-ok marker suite=resolute")
print(f"PASS: linux-stable {linux.get('version')} (resolute 6.14+ docs)")
print(f"PASS: catalog strawwu_version {catalog.get('strawwu_version')} (VERSION {version})")
PY
    ;;
  u26-regression-e2e)
    require_plan "strawwu-ubuntu-2604-migration-plan.md"
    require_file "${PLANS_DIR}/ubuntu-base-target.json" "ubuntu-base-target"
    require_file "${REPO_ROOT}/tests/boot/output/boot-result.json" "boot-result.json"
    require_file "${REPO_ROOT}/tests/install-e2e/output/firstboot-e2e-result.json" "firstboot-e2e-result.json"
    require_file "${REPO_ROOT}/os-image/work/.regression-e2e-ok" "regression-e2e marker"
    PYTHONHASHSEED=0 python3 - \
        "${PLANS_DIR}/ubuntu-base-target.json" \
        "${REPO_ROOT}/VERSION" \
        "${REPO_ROOT}/tests/boot/output/boot-result.json" \
        "${REPO_ROOT}/tests/install-e2e/output/firstboot-e2e-result.json" \
        "${REPO_ROOT}/os-image/output" \
        "${REPO_ROOT}/os-image/work/.regression-e2e-ok" \
        "${REPO_ROOT}/os-image/work/rootfs/etc/os-release" <<'PY'
import json, pathlib, sys

target_path, version_path, boot_path, firstboot_path, iso_dir, marker_path, os_release_path = map(
    pathlib.Path, sys.argv[1:8]
)
target = json.loads(target_path.read_text(encoding="utf-8"))
active = target.get("active", {})
version = version_path.read_text().strip()
boot = json.loads(boot_path.read_text(encoding="utf-8"))
firstboot = json.loads(firstboot_path.read_text(encoding="utf-8"))
marker = marker_path.read_text().strip().split()

if active.get("codename") != "resolute":
    print(f"FAIL: active.codename expected resolute got {active.get('codename')!r}", file=sys.stderr)
    sys.exit(1)

if not version.startswith("0.6"):
    print(f"FAIL: VERSION {version!r} not in 0.6.x preview range", file=sys.stderr)
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

if not marker or marker[0] != "resolute":
    print(f"FAIL: .regression-e2e-ok expected resolute marker got {marker!r}", file=sys.stderr)
    sys.exit(1)
if len(marker) < 2 or marker[1] != version:
    print(f"FAIL: .regression-e2e-ok version {marker[1:]!r} != VERSION {version!r}", file=sys.stderr)
    sys.exit(1)

os_release = os_release_path.read_text(encoding="utf-8") if os_release_path.is_file() else ""
if "VERSION_CODENAME=resolute" not in os_release:
    print("FAIL: rootfs os-release not resolute", file=sys.stderr)
    sys.exit(1)

print(f"PASS: active Ubuntu {active.get('version')} resolute")
print(f"PASS: release ISO StrawWU-{version}-amd64.iso ({iso.stat().st_size // (1024*1024)} MiB)")
print(f"PASS: boot-result {version} BIOS+UEFI STRAWWU_BOOT_OK")
print(f"PASS: firstboot-e2e {version} install+boot+FIRSTBOOT_OK")
print(f"PASS: .regression-e2e-ok resolute {version}")
PY
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

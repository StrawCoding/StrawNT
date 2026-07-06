#!/usr/bin/env bash
# Refresh StrawWU upstream technical references (resolute packages + git shallow).
# Safe to re-run; uses apt-get source and shallow git clones.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/../.." && pwd)"
UP="$ROOT/upstream"
INDEXES="$ROOT/indexes"
WORK="${TMPDIR:-/tmp}/strawwu-docs-fetch-$$"
mkdir -p "$UP" "$WORK"

# Derive APT suite from ubuntu-base-target.json (fallback: resolute).
APT_SUITE="${STRAWWU_APT_SUITE:-}"
if [[ -z "${APT_SUITE}" && -f "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" ]]; then
  APT_SUITE="$(python3 - "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" <<'PY'
import json, pathlib, sys
target = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(target.get("active", {}).get("codename", "resolute"))
PY
)"
fi
APT_SUITE="${APT_SUITE:-resolute}"

KVER="${STRAWWU_KERNEL_DOC_TAG:-}"
if [[ -z "${KVER}" && -f "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" ]]; then
  KVER="$(python3 - "${REPO_ROOT}/docs/plans/ubuntu-base-target.json" <<'PY'
import json, pathlib, sys
target = json.loads(pathlib.Path(sys.argv[1]).read_text())
upstream = target.get("active", {}).get("kernel_upstream", "6.14")
print(f"v{upstream}.9" if upstream.startswith("6.") else f"v{upstream}")
PY
)"
fi
KVER="${KVER:-v6.14.9}"

log() { echo "[refresh-techrefs] $*"; }

log "APT suite: ${APT_SUITE}, kernel docs: ${KVER}"

cd "$WORK"
log "Fetching apt sources (${APT_SUITE})..."
for pkg in casper initramfs-tools calamares calamares-settings-ubuntu-common plymouth libisoburn grub-pc-bin; do
  apt-get source -y -t "${APT_SUITE}" "$pkg" 2>/dev/null || log "warn: apt source $pkg failed"
done

log "Syncing apt trees to $UP ..."
for d in "$WORK"/*; do
  [ -d "$d" ] || continue
  base=$(basename "$d")
  case "$base" in
    casper-*|initramfs-tools-*|calamares-*|calamares-settings-ubuntu-*|plymouth-*|libisoburn-*|grub2-*)
      rsync -a --delete "$d/" "$UP/$base/"
      log "synced $base"
      ;;
  esac
done

clone_shallow() {
  local name="$1" url="$2"
  if [ ! -d "$UP/git-$name/.git" ]; then
    git clone --depth 1 "$url" "$UP/git-$name"
    log "cloned git-$name"
  else
    log "skip git-$name (exists)"
  fi
}

clone_shallow casper https://git.launchpad.net/casper
clone_shallow calamares https://github.com/calamares/calamares.git

LINUX_DIR="linux-${KVER}"
if [ -d "$UP/linux-v6.8.12" ] && [ ! -d "$UP/${LINUX_DIR}" ]; then
  rm -rf "$UP/linux-v6.8.12"
  log "removed stale linux-v6.8.12 docs"
fi
if [ ! -d "$UP/${LINUX_DIR}/.git" ]; then
  git clone --depth 1 --filter=blob:none --sparse -b "$KVER" \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git "$UP/${LINUX_DIR}"
  (cd "$UP/${LINUX_DIR}" && git sparse-checkout set \
    Documentation/admin-guide Documentation/kbuild Documentation/filesystems \
    Documentation/block Documentation/driver-api Documentation/arch/x86)
  log "cloned linux ${KVER} docs"
else
  log "skip ${LINUX_DIR} (exists)"
fi

mkdir -p "$UP/manpages" "$UP/manpages/local" "$UP/guides/xorriso"
for url in \
  "https://manpages.ubuntu.com/manpages/${APT_SUITE}/man7/casper.7.html" \
  "https://manpages.ubuntu.com/manpages/${APT_SUITE}/man8/update-initramfs.8.html" \
  "https://manpages.ubuntu.com/manpages/${APT_SUITE}/man1/xorriso.1.html" \
  "https://manpages.ubuntu.com/manpages/${APT_SUITE}/man8/plymouthd.8.html"; do
  curl -fsSL "$url" -o "$UP/manpages/$(basename "$url")" 2>/dev/null || true
done

for m in casper initramfs-tools update-initramfs xorriso mksquashfs plymouthd grub-install; do
  if man -w "$m" >/dev/null 2>&1; then
    man "$m" 2>/dev/null | col -b > "$UP/manpages/local/${m}.txt" || true
  fi
done

curl -fsSL "https://help.ubuntu.com/community/LiveCDCustomization" \
  -o "$UP/guides/ubuntu_livecd_customization.html" 2>/dev/null || true
cp "$UP/libisoburn-"*/doc/*.txt "$UP/guides/xorriso/" 2>/dev/null || true

rm -rf "$WORK"

# Drop noble-era apt trees superseded by this refresh.
for stale in \
  "$UP/casper-1.498" \
  "$UP/initramfs-tools-0.142ubuntu25.8" \
  "$UP/calamares-3.3.5" \
  "$UP/calamares-settings-ubuntu-24.04.40" \
  "$UP/plymouth-24.004.60" \
  "$UP/grub2-2.12" \
  "$UP/calamares-man"; do
  if [ -e "$stale" ]; then
    rm -rf "$stale"
    log "removed stale ${stale##*/}"
  fi
done

# Regenerate catalog.json from discovered upstream trees.
STRAWWU_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo "0.0.0.0")"
TOTAL_SIZE="$(du -sh "$ROOT" 2>/dev/null | cut -f1 || echo "?")"
PYTHONHASHSEED=0 python3 - \
  "${INDEXES}/catalog.json" \
  "${APT_SUITE}" \
  "${KVER}" \
  "${STRAWWU_VERSION}" \
  "${TOTAL_SIZE}" \
  "${UP}" <<'PY'
import json, pathlib, re, sys
from datetime import datetime, timezone

catalog_path, suite, kver, strawwu_ver, total_size, up = sys.argv[1:7]
up = pathlib.Path(up)

def find_dir(prefix: str, *, version_re: str = r"[0-9]") -> tuple[str, str]:
    pat = re.compile(rf"^{re.escape(prefix)}-({version_re})")
    matches = sorted(
        (p for p in up.glob(f"{prefix}-*") if p.is_dir() and pat.match(p.name)),
        key=lambda p: p.name,
    )
    if not matches:
        return "", ""
    d = matches[-1]
    ver = d.name[len(prefix) + 1 :]
    return ver, d.name

casper_v, casper_dir = find_dir("casper")
initrd_v, initrd_dir = find_dir("initramfs-tools")
plymouth_v, plymouth_dir = find_dir("plymouth")
isoburn_v, isoburn_dir = find_dir("libisoburn")
grub_v, grub_dir = find_dir("grub2")
cal_v, cal_dir = find_dir("calamares", version_re=r"3\.")
# calamares-settings-ubuntu source unpacks as calamares-settings-ubuntu-<ver>
cs_dirs = sorted(up.glob("calamares-settings-ubuntu-*"), key=lambda p: p.name)
cs_dir = cs_dirs[-1].name if cs_dirs else ""
cs_v = cs_dir.replace("calamares-settings-ubuntu-", "") if cs_dir else ""

catalog = {
    "updated_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "ubuntu_release": suite,
    "strawwu_version": strawwu_ver,
    "total_size_human": total_size,
    "refresh_script": "docs/technical-references/scripts/refresh-technical-references.sh",
    "packages": [],
    "manpages": {"html": "upstream/manpages/", "local_txt": "upstream/manpages/local/"},
    "guides": [
        {
            "title": "Ubuntu LiveCD Customization",
            "path": "upstream/guides/ubuntu_livecd_customization.html",
            "url": "https://help.ubuntu.com/community/LiveCDCustomization",
        }
    ],
    "strawwu_validation_commands": {
        "phase1": ["make preflight", "make boot-test-release-iso"],
        "phase2": [
            "make preflight-iso-before-boot",
            "make release-iso",
            "make boot-test-release-iso",
            "make test-phase2",
        ],
        "phase3": ["make validate-calamares-preflight", "make test-install-e2e"],
    },
}

def add_pkg(name, version, path, phases, key_files, git=None):
    if not path:
        return
    entry = {"name": name, "version": version, "path": f"upstream/{path}", "phases": phases, "key_files": key_files}
    if git:
        entry["git"] = git
    catalog["packages"].append(entry)

add_pkg("casper", casper_v, casper_dir, ["phase1-ubuntu-clone", "phase2-custom-kernel"],
        ["hooks/", "scripts/", "debian/manpage/casper.7"], "https://git.launchpad.net/casper")
add_pkg("initramfs-tools", initrd_v, initrd_dir, ["phase2-custom-kernel"],
        ["hooks/", "scripts/", "docs/"],
        "https://git.launchpad.net/~ubuntu-core-dev/ubuntu/+source/initramfs-tools")
add_pkg("plymouth", plymouth_v, plymouth_dir, ["phase2-custom-kernel"], ["docs/", "themes/", "src/"])
add_pkg("libisoburn", isoburn_v, isoburn_dir,
        ["phase1-ubuntu-clone", "phase2-custom-kernel", "v3.0-release"], ["doc/", "xorriso/"])
add_pkg("grub2", grub_v, grub_dir,
        ["phase1-ubuntu-clone", "phase2-custom-kernel", "phase3-calamares-e2e"], ["docs/", "grub-core/"])
add_pkg("calamares", cal_v, cal_dir, ["phase3-calamares-e2e"], ["man/", "src/"],
        "https://github.com/calamares/calamares")
add_pkg("calamares-settings-ubuntu-common", cs_v, cs_dir, ["phase3-calamares-e2e"],
        ["etc/calamares/", "usr/share/calamares/"],
        "https://code.launchpad.net/~ubuntu-qt-code/+git/calamares-settings-ubuntu")
linux_path = f"linux-{kver}"
add_pkg("linux-stable", kver, linux_path, ["phase2-custom-kernel", "phase4-greenfield"],
        [
            "Documentation/kbuild/",
            "Documentation/filesystems/overlayfs.rst",
            "Documentation/filesystems/isofs.rst",
            "Documentation/driver-api/",
        ],
        "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git")

pathlib.Path(catalog_path).write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"[refresh-techrefs] catalog.json updated ({len(catalog['packages'])} packages, suite={suite})")
PY

MARKER="${ROOT}/.techrefs-refresh-ok"
printf '%s %s %s\n' "${APT_SUITE}" "${KVER}" "${STRAWWU_VERSION}" > "${MARKER}"
log "marker ${MARKER}"
log "Done. Total: ${TOTAL_SIZE}"
log "See indexes/phase-validation-map.md for Phase mapping."

#!/usr/bin/env bash
# Refresh StrawWU upstream technical references (noble packages + git shallow).
# Safe to re-run; uses apt-get source and shallow git clones.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UP="$ROOT/upstream"
WORK="${TMPDIR:-/tmp}/strawwu-docs-fetch-$$"
mkdir -p "$UP" "$WORK"
cd "$WORK"

log() { echo "[refresh-techrefs] $*"; }

log "Fetching apt sources (noble)..."
for pkg in casper initramfs-tools calamares calamares-settings-ubuntu plymouth libisoburn grub-pc-bin; do
  apt-get source -y "$pkg" 2>/dev/null || log "warn: apt source $pkg failed"
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

KVER="v6.8.12"
if [ ! -d "$UP/linux-$KVER/.git" ]; then
  git clone --depth 1 --filter=blob:none --sparse -b "$KVER" \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git "$UP/linux-$KVER"
  (cd "$UP/linux-$KVER" && git sparse-checkout set \
    Documentation/admin-guide Documentation/kbuild Documentation/filesystems \
    Documentation/block Documentation/driver-api Documentation/arch/x86)
  log "cloned linux $KVER docs"
fi

mkdir -p "$UP/manpages" "$UP/manpages/local" "$UP/guides/xorriso"
for url in \
  "https://manpages.ubuntu.com/manpages/noble/man7/casper.7.html" \
  "https://manpages.ubuntu.com/manpages/noble/man8/update-initramfs.8.html" \
  "https://manpages.ubuntu.com/manpages/noble/man1/xorriso.1.html" \
  "https://manpages.ubuntu.com/manpages/noble/man8/plymouthd.8.html"; do
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
log "Done. Total: $(du -sh "$ROOT" | cut -f1)"
log "See indexes/phase-validation-map.md for Phase mapping."

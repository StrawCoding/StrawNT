#!/usr/bin/env bash
# chroot-nosnap-harden.sh — W1-F2: mask snapd meta Recommends, stub /snap, apt pin.
#
# Idempotent chroot hook after purge + flatpak setup. Syncs rootfs → squashfs-root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SQUASH_SRC="${WORK_DIR}/squashfs-root"
MARKER="${WORK_DIR}/.nosnap-harden-ok"
CLONE_MARKER="${WORK_DIR}/.clone-ubuntu-base-ok"
PURGE_MARKER="${WORK_DIR}/.purge-ubuntu-telemetry-ok"
AUDIT_JSON="${REPO_ROOT}/docs/plans/baselines/nosnap-audit.json"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (chroot nosnap harden)"
}

unmount_chroot() {
    umount "${ROOTFS_DIR}/run" 2>/dev/null || umount -l "${ROOTFS_DIR}/run" 2>/dev/null || true
    umount "${ROOTFS_DIR}/dev/pts" 2>/dev/null || umount -l "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    umount "${ROOTFS_DIR}/sys" 2>/dev/null || umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
    umount "${ROOTFS_DIR}/proc" 2>/dev/null || umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
    umount "${ROOTFS_DIR}/dev" 2>/dev/null || umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
}

chroot_run() {
    mount --bind /dev  "${ROOTFS_DIR}/dev"
    mount --bind /proc "${ROOTFS_DIR}/proc"
    mount --bind /sys  "${ROOTFS_DIR}/sys"
    mount -t devpts devpts "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    mount --bind /run  "${ROOTFS_DIR}/run" 2>/dev/null || true
    trap 'unmount_chroot' EXIT
    chroot "${ROOTFS_DIR}" "$@"
    local rc=$?
    unmount_chroot
    trap - EXIT
    return "${rc}"
}

verify_prerequisites() {
    [[ -f "${CLONE_MARKER}" ]] || die "run clone-ubuntu-base first (${CLONE_MARKER} missing)"
    [[ -f "${PURGE_MARKER}" ]] || die "run chroot-purge-ubuntu-telemetry first (${PURGE_MARKER} missing)"
    [[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing: ${ROOTFS_DIR}"
    unmount_chroot
}

harden_in_chroot() {
    log "applying nosnap hardening inside chroot"
    cp -f /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true

    local inner="${WORK_DIR}/chroot-nosnap-inner.sh"
    cat > "${inner}" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

systemctl disable snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
systemctl mask snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true

apt-mark hold snapd snap-confine firefox thunderbird 2>/dev/null || true

mkdir -p /etc/apt/preferences.d
cat > /etc/apt/preferences.d/strawwu-nosnap <<'PREF'
# StrawWU W1-F2 — block snapd re-install via ubuntu-desktop Recommends.
Package: snapd snap-confine ubuntu-core*
Pin: release *
Pin-Priority: -1
PREF

for snap_dir in /var/lib/snapd /root/snap; do
    [[ -d "${snap_dir}" ]] && rm -rf "${snap_dir}"
done
find /home -maxdepth 2 -type d -name snap -exec rm -rf {} + 2>/dev/null || true

mkdir -p /snap
cat > /snap/README <<'README'
StrawWU does not ship snapd. This directory is an empty stub so legacy
paths remain valid. Install apps via Flatpak (Flathub) or apt.
README
chmod 755 /snap
chmod 644 /snap/README

dpkg --purge --force-all snapd snap-confine 2>/dev/null || true
apt-get purge -y snapd snap-confine 2>/dev/null || true
INNER
    chmod +x "${inner}"
    mkdir -p "${ROOTFS_DIR}/tmp"
    cp -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-nosnap-inner.sh"
    chroot_run bash /tmp/chroot-nosnap-inner.sh
    rm -f "${inner}" "${ROOTFS_DIR}/tmp/chroot-nosnap-inner.sh"
}

write_audit_json() {
    local version="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.4.0.0)}"
    mkdir -p "$(dirname "${AUDIT_JSON}")"

    python3 - "${ROOTFS_DIR}" "${AUDIT_JSON}" "${version}" <<'PY'
import json, re, sys
from pathlib import Path

rootfs = Path(sys.argv[1])
out = Path(sys.argv[2])
version = sys.argv[3]
status = (rootfs / "var/lib/dpkg/status").read_text(errors="replace")

def installed(name):
    for block in re.split(r"\n(?=Package: )", status):
        m = re.match(rf"^Package: {re.escape(name)}\n", block)
        if not m:
            continue
        sm = re.search(r"^Status: (.+)$", block, re.M)
        return bool(sm and " ok installed" in sm.group(1))
    return False

def meta_snap_refs():
    meta = ["ubuntu-desktop", "ubuntu-desktop-minimal", "ubuntu-minimal", "ubuntu-standard"]
    refs = []
    blocks = re.split(r"\n(?=Package: )", status)
    for block in blocks:
        m = re.match(r"^Package: (.+)$", block, re.M)
        if not m or m.group(1) not in meta:
            continue
        pkg = m.group(1)
        for field in ("Depends", "Pre-Depends", "Recommends", "Suggests"):
            fm = re.search(rf"^{field}: (.+)$", block, re.M)
            if fm and re.search(r"\bsnapd\b|\bsnap-confine\b", fm.group(1)):
                refs.append({"package": pkg, "field": field, "masked": field == "Recommends"})
    return refs

client_libs = [p for p in ("libsnapd-glib-2-1", "gir1.2-snapd-2") if installed(p)]
snap_stub = (rootfs / "snap").is_dir()
snap_content = 0
if snap_stub:
    snap_content = len([x for x in (rootfs / "snap").iterdir() if x.name != "README"])

data = {
    "schema": "strawwu-nosnap-audit/v1",
    "wave": "W1-F2",
    "version": version,
    "snapd_installed": installed("snapd"),
    "snap_confine_installed": installed("snap-confine"),
    "meta_snap_references": meta_snap_refs(),
    "client_libs_without_snapd": client_libs,
    "client_libs_note": "libsnapd-glib is a D-Bus client; acceptable while snapd daemon absent",
    "apt_pin": "/etc/apt/preferences.d/strawwu-nosnap",
    "apt_pin_present": (rootfs / "etc/apt/preferences.d/strawwu-nosnap").is_file(),
    "snap_mount_stub": snap_stub,
    "snap_content_dirs": snap_content,
    "var_lib_snapd_absent": not (rootfs / "var/lib/snapd").exists(),
}

out.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
    log "nosnap audit written: ${AUDIT_JSON}"
}

sync_squashfs_baseline() {
    [[ "${STRAWWU_SKIP_SQUASHFS_SYNC:-0}" == "1" ]] && {
        log "STRAWWU_SKIP_SQUASHFS_SYNC=1: skip squashfs-root sync"
        return 0
    }
    log "syncing nosnap rootfs → squashfs-root for preflight baseline"
    rsync -a --delete \
        --exclude='dev/' \
        --exclude='proc/' \
        --exclude='sys/' \
        --exclude='run/' \
        "${ROOTFS_DIR}/" "${SQUASH_SRC}/"
}

verify_harden() {
    local status="${ROOTFS_DIR}/var/lib/dpkg/status"
    for pkg in snapd snap-confine; do
        if awk -v p="${pkg}" '
            /^Package: / { cur=$2 }
            /^Status: / && / ok installed/ && cur==p { found=1 }
            END { exit !found }
        ' "${status}"; then
            die "still installed after nosnap harden: ${pkg}"
        fi
    done

    [[ -f "${ROOTFS_DIR}/etc/apt/preferences.d/strawwu-nosnap" ]] \
        || die "missing apt pin: /etc/apt/preferences.d/strawwu-nosnap"

    if [[ -d "${ROOTFS_DIR}/snap" ]]; then
        local snap_count
        snap_count="$(find "${ROOTFS_DIR}/snap" -mindepth 1 -maxdepth 1 ! -name README 2>/dev/null | wc -l || echo 0)"
        [[ "${snap_count}" -eq 0 ]] || die "/snap has ${snap_count} non-stub entries"
    fi

    [[ ! -d "${ROOTFS_DIR}/var/lib/snapd" ]] || die "/var/lib/snapd still present"
    log "post-harden verification OK"
}

main() {
    need_root
    verify_prerequisites

    if [[ -f "${MARKER}" && "${STRAWWU_FORCE:-0}" != "1" ]]; then
        log "nosnap harden already done ($(cat "${MARKER}")); set STRAWWU_FORCE=1 to redo"
        write_audit_json
        exit 0
    fi

    harden_in_chroot
    verify_harden
    write_audit_json
    sync_squashfs_baseline

    date -Is > "${MARKER}"
    log "nosnap harden complete: ${ROOTFS_DIR}"
}

main "$@"

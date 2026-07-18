#!/usr/bin/env bash
# patch-iso-secureboot-fallback.sh — Live USB GRUB policy for physical displays.
#
# Root causes (POST-HW-T1 physical blank) addressed here:
#   A) SB-off used to default to custom -strawwu kernel (QEMU virtio hid it).
#   B) console=ttyS0 (for QEMU markers) makes Plymouth bind the serial seat and
#      leave the real panel black — must pair with plymouth.ignore-serial-consoles.
# Canonical *-generic + Ubuntu initrd-generic is the proven Live display path.
#
# Policy:
#   1) Default "Try or Install" → vmlinuz-generic + initrd-generic (Ubuntu path)
#   2) "custom kernel (MOK)" → try MOK-signed strawwu, fall back to generic
#   3) Safe graphics / Rescue → generic (+ nomodeset / rescue)
#   4) Keep ttyS0 for QEMU + plymouth.ignore-serial-consoles for physical panel
#
# Run AFTER console/rescue grub patches (final grub authority).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ISO_STAGING="${WORK_DIR}/iso-staging"

log() { echo "==> $*" >&2; }

patch_cfg() {
    local cfg="$1"
    [[ -f "${cfg}" ]] || return 0
    python3 - "${cfg}" <<'PY'
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
text = cfg.read_text(encoding="utf-8")

# Idempotent: already rewritten to live-default-generic + physical plymouth policy.
if (
    "StrawWU custom kernel (MOK)" in text
    and "plymouth.ignore-serial-consoles" in text
    and re.search(
        r'menuentry\s+"Try or Install StrawWU"\s*\{[^}]*vmlinuz-generic',
        text,
        flags=re.DOTALL,
    )
):
    print(f"already live-default-generic: {cfg}", file=sys.stderr)
    sys.exit(0)

def linux_args(block: str) -> str:
    m = re.search(r"linux\s+/casper/vmlinuz(?:-generic)?(?P<args>(?:[ \t][^\n]*)?)", block)
    return (m.group("args") if m else "") or ""

def strip_nomodeset(args: str) -> str:
    return re.sub(r"[ \t]+nomodeset\b", "", args)

def ensure_nomodeset(args: str) -> str:
    args = strip_nomodeset(args)
    # Insert before '---' when present so it stays a kernel arg.
    if "---" in args:
        return args.replace("---", "nomodeset ---", 1)
    return args + " nomodeset"

def ensure_rescue(args: str) -> str:
    if "strawwu_rescue=1" in args:
        return args
    if "---" in args:
        return args.replace("---", "strawwu_rescue=1 ---", 1)
    return args + " strawwu_rescue=1"

def ensure_plymouth_physical(args: str) -> str:
    """Keep Plymouth/GDM on the panel when ttyS0 is present for QEMU markers."""
    if "plymouth.ignore-serial-consoles" in args:
        return args
    token = "plymouth.ignore-serial-consoles"
    if "console=ttyS0" in args:
        return args.replace("console=ttyS0,115200n8", f"console=ttyS0,115200n8 {token}", 1) \
            if "console=ttyS0,115200n8" in args else args.replace("console=ttyS0", f"console=ttyS0 {token}", 1)
    if "---" in args:
        return args.replace("---", f"{token} ---", 1)
    return args + f" {token}"

# Pull args from the first linux line (post console patch).
first = re.search(
    r"linux[ \t]+/casper/vmlinuz(?:-generic)?(?P<args>(?:[ \t][^\n]*)?)",
    text,
)
default_args = (
    " boot=casper console=tty0 console=ttyS0,115200n8 "
    "plymouth.ignore-serial-consoles username=ubuntu  --- quiet splash"
)
base_args = ensure_plymouth_physical(
    strip_nomodeset(first.group("args") if first else default_args)
)
safe_args = ensure_nomodeset(base_args)
rescue_args = ensure_rescue(base_args)

# Preserve trailing EFI helper entries if present.
efi_tail = ""
m_efi = re.search(r"\nif \[ \"\$grub_platform\" = \"efi\" \]; then\n.*\nfi\n?\Z", text, flags=re.DOTALL)
if m_efi:
    efi_tail = m_efi.group(0)
    text_head = text[: m_efi.start()]
else:
    text_head = text

# Keep timeout / font / colors from the original head.
header_m = re.match(
    r"(?P<header>(?:(?!^menuentry).)*\n)",
    text_head,
    flags=re.DOTALL | re.MULTILINE,
)
header = header_m.group("header") if header_m else "set timeout=30\n\nloadfont unicode\n\n"

new_text = f"""{header.rstrip()}

menuentry "Try or Install StrawWU" {{
    set gfxpayload=keep
    linux /casper/vmlinuz-generic{base_args}
    initrd /casper/initrd-generic
}}
menuentry "StrawWU custom kernel (MOK)" {{
    set gfxpayload=keep
    linux /casper/vmlinuz{base_args}
    if [ "$?" = 0 ]; then
        initrd /casper/initrd
    else
        echo "StrawWU: Secure Boot without enrolled MOK - booting signed fallback kernel"
        linux /casper/vmlinuz-generic{base_args}
        initrd /casper/initrd-generic
    fi
}}
menuentry 'StrawWU Rescue' {{
    set gfxpayload=keep
    linux /casper/vmlinuz-generic{rescue_args}
    initrd /casper/initrd-generic
}}
menuentry "StrawWU (safe graphics)" {{
    set gfxpayload=keep
    linux /casper/vmlinuz-generic{safe_args}
    initrd /casper/initrd-generic
}}
{efi_tail.lstrip()}
"""
cfg.write_text(new_text, encoding="utf-8")
print(f"patched live-default-generic GRUB policy: {cfg}", file=sys.stderr)
PY
}

sanitize_live_layer() {
    # Ubuntu minimal.standard.live.squashfs overlays snap bootstrap +
    # display-manager After=snapd.seeded while StrawWU purged snapd. Rebuild a
    # sanitized live layer: drop snap installer units, pin StrawWU casper.conf.
    local live_sq="${ISO_STAGING}/casper/minimal.standard.live.squashfs"
    [[ -f "${live_sq}" ]] || {
        log "no live layer — skip sanitize"
        return 0
    }
    local tmp="${WORK_DIR}/.live-sanitize"
    local branding_casper="${REPO_ROOT}/os-image/config/branding/etc/casper.conf"
    rm -rf "${tmp}"
    mkdir -p "${tmp}"
    log "sanitizing live layer (remove snap bootstrap; pin casper.conf)"
    unsquashfs -force -ignore-errors -d "${tmp}" "${live_sq}" >/dev/null
    rm -f \
        "${tmp}/etc/systemd/system/display-manager.service.d/wait-for-snapd-seeding.conf" \
        "${tmp}/etc/systemd/system/snap.ubuntu-desktop-bootstrap.subiquity-server.service" \
        "${tmp}/etc/polkit-1/rules.d/10-allow-installer-wait-on-snap.rules"
    rm -f "${tmp}/etc/systemd/system"/snap-ubuntu*bootstrap*.mount 2>/dev/null || true
    rm -rf "${tmp}/etc/systemd/system/snapd.service.d" \
        "${tmp}/etc/systemd/system/display-manager.service.d"
    # Drop wants/symlinks and snap userland left by ubuntu-desktop-bootstrap.
    find "${tmp}/etc/systemd" -name '*ubuntu*bootstrap*' -delete 2>/dev/null || true
    find "${tmp}/etc/systemd" -name '*snapd*' -delete 2>/dev/null || true
    rm -rf "${tmp}/snap/ubuntu-desktop-bootstrap" \
        "${tmp}/snap/bin" \
        "${tmp}/var/lib/snapd" \
        "${tmp}/var/cache/snapd" \
        "${tmp}/var/cache/apparmor" \
        "${tmp}/var/snap"
    # Drop seeded snap payloads that cannot run without snapd.
    rm -rf "${tmp}/var/lib/snapd/seed" \
        "${tmp}/var/lib/snapd/snaps" \
        "${tmp}/var/lib/snapd/apparmor" \
        "${tmp}/var/lib/snapd/mount" \
        "${tmp}/var/lib/snapd/cookie"
    if [[ -f "${branding_casper}" ]]; then
        mkdir -p "${tmp}/etc"
        cp -a "${branding_casper}" "${tmp}/etc/casper.conf"
        # Ensure FLAVOUR so casper keeps USERNAME=ubuntu from branding.
        if ! grep -q '^export FLAVOUR=' "${tmp}/etc/casper.conf"; then
            printf '\nexport FLAVOUR="StrawWU"\nexport HOST="strawwu"\n' >> "${tmp}/etc/casper.conf"
        fi
    fi

    # Physical display: DeviceTimeout + gnome-shell mode CSS path (stylesheetName).
    local branding_plymouth="${REPO_ROOT}/os-image/config/branding/etc/plymouth/plymouthd.conf"
    local branding_shell_css="${REPO_ROOT}/os-image/config/branding/usr/share/themes/StrawWU-Dark/gnome-shell"
    if [[ -f "${branding_plymouth}" ]]; then
        mkdir -p "${tmp}/etc/plymouth"
        cp -a "${branding_plymouth}" "${tmp}/etc/plymouth/plymouthd.conf"
    fi
    if [[ -d "${branding_shell_css}" ]]; then
        mkdir -p "${tmp}/usr/share/gnome-shell/theme/StrawWU-Dark"
        cp -a "${branding_shell_css}/." "${tmp}/usr/share/gnome-shell/theme/StrawWU-Dark/"
    fi
    chmod u+w "${live_sq}" 2>/dev/null || true
    rm -f "${live_sq}"
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/iso-mode.sh"
    iso_mode_resolve
    local -a comp_args=()
    iso_mode_squashfs_args comp_args
    mksquashfs "${tmp}" "${live_sq}" "${comp_args[@]}" -e boot
    rm -rf "${tmp}"
    if [[ -f "${ISO_STAGING}/casper/minimal.standard.live.size" ]]; then
        local size
        size="$(du -sb "${live_sq}" | cut -f1)"
        echo -n "${size}" > "${ISO_STAGING}/casper/minimal.standard.live.size"
    fi
    log "live layer sanitized: $(du -h "${live_sq}" | awk '{print $1}')"
}

main() {
    [[ -d "${ISO_STAGING}" ]] || {
        log "iso-staging missing — skip Secure Boot / live-default patch"
        exit 0
    }
    if [[ ! -f "${ISO_STAGING}/casper/vmlinuz-generic" || ! -f "${ISO_STAGING}/casper/initrd-generic" ]]; then
        log "no staged Secure Boot fallback kernel/initrd — skip fallback grub patch"
        exit 0
    fi

    sanitize_live_layer

    for cfg in \
        "${ISO_STAGING}/boot/grub/grub.cfg" \
        "${ISO_STAGING}/boot/grub/loopback.cfg" \
        "${ISO_STAGING}/isolinux/grub.cfg"; do
        patch_cfg "${cfg}"
    done
    log "Live-default-generic + Secure Boot custom-entry grub patch complete"
}

main "$@"

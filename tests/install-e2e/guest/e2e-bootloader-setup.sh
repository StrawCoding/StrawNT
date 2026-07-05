#!/bin/sh
# e2e-bootloader-setup.sh — runs on live system (dontChroot=true context)
# Copies kernel from ISO, configures GRUB serial console, installs GRUB.
set -e

ROOT="/tmp/calamares-root"
DEV="/dev/vda"

# Partition shellprocess creates ${DEV}1 (ESP) and ${DEV}2 (root). Ensure both
# stay mounted through initramfs — UEFI grub-install needs ESP.
ensure_target_mounts() {
    local root_part="${DEV}3"
    local efi_part="${DEV}1"
    mkdir -p "$ROOT"
    if ! mountpoint -q "$ROOT" 2>/dev/null; then
        mount "${root_part}" "$ROOT" || {
            echo "ERROR: cannot mount ${root_part} on $ROOT" >&2
            exit 1
        }
        echo "Remounted ${root_part} on $ROOT"
    fi
    mkdir -p "$ROOT/boot/efi"
    if ! mountpoint -q "$ROOT/boot/efi" 2>/dev/null; then
        mount "${efi_part}" "$ROOT/boot/efi" || {
            echo "ERROR: cannot mount ESP ${efi_part} on $ROOT/boot/efi" >&2
            exit 1
        }
        echo "Mounted ESP ${efi_part} on $ROOT/boot/efi"
    fi
}
ensure_target_mounts

# Detect kernel version from installed modules
KVER=$(ls "$ROOT/lib/modules/" 2>/dev/null | sort -V | tail -1)
if [ -z "$KVER" ]; then
    echo "WARN: no kernel modules found, using uname -r" >&2
    KVER=$(uname -r)
fi

# Copy kernel and initrd from live ISO
if [ -f /cdrom/casper/vmlinuz ]; then
    mkdir -p "$ROOT/boot/grub"
    cp /cdrom/casper/vmlinuz "$ROOT/boot/vmlinuz-$KVER"
    ln -sf "vmlinuz-$KVER" "$ROOT/boot/vmlinuz"
    echo "Kernel $KVER copied to $ROOT/boot/"
else
    echo "ERROR: /cdrom/casper/vmlinuz not found" >&2
    exit 1
fi

# Remove casper/live-boot initramfs hooks so update-initramfs generates a
# standard disk-boot initramfs (not a live-media one that loops on /dev/sr0).
rm -f  "$ROOT/usr/share/initramfs-tools/hooks/casper"
rm -rf "$ROOT/usr/share/initramfs-tools/scripts/casper"*
rm -f  "$ROOT/usr/share/initramfs-tools/hooks/live-boot"
rm -rf "$ROOT/usr/share/initramfs-tools/scripts/live"*
rm -f  "$ROOT/usr/share/initramfs-tools/conf.d/casper"
rm -f  "$ROOT/etc/initramfs-tools/conf.d/casper"
echo "Casper/live-boot hooks removed from chroot"

# Ensure BOOT= is set to local for standard disk boot
mkdir -p "$ROOT/etc/initramfs-tools"
if ! grep -q '^BOOT=local' "$ROOT/etc/initramfs-tools/initramfs.conf" 2>/dev/null; then
    sed -i 's/^BOOT=.*/BOOT=local/' "$ROOT/etc/initramfs-tools/initramfs.conf" 2>/dev/null || \
        echo "BOOT=local" >> "$ROOT/etc/initramfs-tools/initramfs.conf"
fi

# Generate proper standard initramfs inside the chroot
rm -f "$ROOT/boot/initrd.img-$KVER"
chroot "$ROOT" update-initramfs -c -k "$KVER" 2>&1
ln -sf "initrd.img-$KVER" "$ROOT/boot/initrd.img"
echo "Standard initramfs generated for $KVER"

# Write /etc/default/grub with serial console
cat > "$ROOT/etc/default/grub" <<'GRUBCFG'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="StrawWU"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=ttyS0,115200n8"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB_DISABLE_OS_PROBER=true
GRUBCFG

# Boot marker systemd service
cat > "$ROOT/etc/systemd/system/strawwu-boot-marker.service" <<'SVC'
[Unit]
Description=StrawWU E2E Boot Marker
DefaultDependencies=no
After=local-fs.target sysinit.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo STRAWWU_BOOT_OK > /dev/ttyS0"
ExecStartPost=/bin/sh -c "echo STRAWWU-DESKTOP-OK > /dev/ttyS0"

[Install]
WantedBy=multi-user.target
SVC
mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/strawwu-boot-marker.service \
    "$ROOT/etc/systemd/system/multi-user.target.wants/strawwu-boot-marker.service"

# Firstboot E2E: headless completion + serial FIRSTBOOT_OK (runs after multi-user, no cycle).
OVERLAY="/mnt/strawwu-e2e/firstboot-e2e-overlay"
if [ -d "$OVERLAY/usr/lib/strawwu-firstboot" ]; then
    mkdir -p "$ROOT/usr/lib/strawwu-firstboot" "$ROOT/usr/bin"
    cp -f "$OVERLAY/usr/lib/strawwu-firstboot/"*.py "$ROOT/usr/lib/strawwu-firstboot/" 2>/dev/null || true
    cp -f "$OVERLAY/usr/bin/strawwu-firstboot" "$ROOT/usr/bin/strawwu-firstboot" 2>/dev/null || true
    chmod 755 "$ROOT/usr/bin/strawwu-firstboot" 2>/dev/null || true
    echo "Firstboot E2E overlay applied from 9p guest share"
fi

cat > "$ROOT/etc/systemd/system/strawwu-firstboot-e2e.service" <<'FBsvc'
[Unit]
Description=StrawWU firstboot E2E (headless)
After=multi-user.target strawwu-boot-marker.service

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c 'command -v strawwu-initd >/dev/null && strawwu-initd init || true'
ExecStart=/usr/bin/strawwu-firstboot run --e2e
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FBsvc
ln -sf /etc/systemd/system/strawwu-firstboot-e2e.service \
    "$ROOT/etc/systemd/system/multi-user.target.wants/strawwu-firstboot-e2e.service"

# Generate GRUB config
chroot "$ROOT" update-grub 2>&1 || chroot "$ROOT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || true

# Install GRUB to MBR (BIOS boot)
grub-install --target=i386-pc --boot-directory="$ROOT/boot" --recheck --force "$DEV"

# UEFI boot: install GRUB to ESP (uses live-system grub-efi; no chroot apt/network).
if mountpoint -q "$ROOT/boot/efi" 2>/dev/null; then
    if [ ! -d "$ROOT/boot/grub/x86_64-efi" ] && [ -d /usr/lib/grub/x86_64-efi ]; then
        mkdir -p "$ROOT/boot/grub/x86_64-efi"
        cp -a /usr/lib/grub/x86_64-efi/. "$ROOT/boot/grub/x86_64-efi/" 2>/dev/null || true
    fi
    if ! grub-install --target=x86_64-efi \
        --efi-directory="$ROOT/boot/efi" \
        --boot-directory="$ROOT/boot" \
        --no-nvram \
        --recheck --force 2>&1; then
        echo "ERROR: grub-install x86_64-efi failed" >&2
        exit 1
    fi
    # OVMF fallback when NVRAM has no Boot#### entry (QEMU installed-boot test).
    mkdir -p "$ROOT/boot/efi/EFI/BOOT"
    for candidate in \
        "$ROOT/boot/efi/EFI/StrawWU/grubx64.efi" \
        "$ROOT/boot/efi/EFI/strawwu/grubx64.efi" \
        "$ROOT/boot/efi/EFI/ubuntu/grubx64.efi" \
        "$ROOT/boot/efi/EFI/BOOT/grubx64.efi"; do
        if [ -f "$candidate" ]; then
            cp -f "$candidate" "$ROOT/boot/efi/EFI/BOOT/BOOTX64.EFI"
            echo "UEFI fallback BOOTX64.EFI from $(basename "$(dirname "$candidate")")"
            break
        fi
    done
    if [ ! -f "$ROOT/boot/efi/EFI/BOOT/BOOTX64.EFI" ]; then
        echo "ERROR: BOOTX64.EFI fallback missing on ESP" >&2
        exit 1
    fi
    # Removable-media UEFI path loads EFI/BOOT/grub.cfg (not EFI/strawwu/grub.cfg).
    if [ -f "$ROOT/boot/efi/EFI/strawwu/grub.cfg" ]; then
        cp -f "$ROOT/boot/efi/EFI/strawwu/grub.cfg" "$ROOT/boot/efi/EFI/BOOT/grub.cfg"
        echo "UEFI fallback grub.cfg installed at EFI/BOOT/grub.cfg"
    fi
    echo "UEFI GRUB installed on ESP"
else
    echo "ERROR: $ROOT/boot/efi not mounted — cannot install UEFI GRUB" >&2
    exit 1
fi

sync
echo "Bootloader setup complete"

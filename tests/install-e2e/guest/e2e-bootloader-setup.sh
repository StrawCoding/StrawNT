#!/bin/sh
# e2e-bootloader-setup.sh — runs on live system (dontChroot=true context)
# Copies kernel from ISO, configures GRUB serial console, installs GRUB.
set -e

ROOT="/tmp/calamares-root"
DEV="/dev/vda"

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
After=multi-user.target

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

# Generate GRUB config
chroot "$ROOT" update-grub 2>&1 || chroot "$ROOT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || true

# Install GRUB to MBR
grub-install --target=i386-pc --boot-directory="$ROOT/boot" --recheck --force "$DEV"

sync
echo "Bootloader setup complete"

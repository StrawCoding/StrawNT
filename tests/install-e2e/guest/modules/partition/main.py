#!/usr/bin/env python3
"""
partition — Custom Calamares Python job replacing the C++ partition ViewStep.
The C++ partition module in Calamares 3.3.5 has a widget update loop that blocks
the Qt event loop entirely. This Python job partitions the target disk, mounts it,
and populates GlobalStorage so downstream modules (unpackfs, fstab, bootloader)
work normally.

Layout (GPT): ESP (UEFI) + BIOS boot (GRUB on GPT) + root — supports W6-I4
installed BIOS+UEFI boot E2E.
"""
import os
import subprocess
import libcalamares


def run_cmd(cmd):
    libcalamares.utils.debug(f"partition(python): {cmd}")
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode != 0:
        libcalamares.utils.warning(f"cmd failed rc={r.returncode}: {cmd}\nstderr: {r.stderr}")
        return False
    return True


def get_uuid(device):
    r = subprocess.run(["blkid", "-s", "UUID", "-o", "value", device],
                       capture_output=True, text=True)
    return r.stdout.strip()


def run():
    gs = libcalamares.globalstorage
    dev = os.environ.get("STRAWWU_E2E_TARGET_DEV", "/dev/vda")
    root_mp = "/tmp/calamares-root"

    libcalamares.utils.debug(f"partition(python): target={dev} rootMountPoint={root_mp}")

    if not run_cmd(f"sgdisk --zap-all {dev}"):
        return ("partition(python): failed to zap disk", "sgdisk --zap-all failed")
    if not run_cmd(f"sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI {dev}"):
        return ("partition(python): failed to create EFI partition", "")
    if not run_cmd(f"sgdisk -n 2:0:+2M -t 2:ef02 -c 2:BIOS {dev}"):
        return ("partition(python): failed to create BIOS boot partition", "")
    if not run_cmd(f"sgdisk -n 3:0:0 -t 3:8300 -c 3:root {dev}"):
        return ("partition(python): failed to create root partition", "")
    run_cmd(f"partprobe {dev}")
    run_cmd("sleep 2")

    efi_dev = f"{dev}1"
    root_dev = f"{dev}3"

    if not run_cmd(f"mkfs.fat -F32 {efi_dev}"):
        return ("partition(python): mkfs.fat ESP failed", "")
    if not run_cmd(f"mkfs.ext4 -F -L strawwu-root {root_dev}"):
        return ("partition(python): mkfs.ext4 failed", "")

    os.makedirs(root_mp, exist_ok=True)
    if not run_cmd(f"mount {root_dev} {root_mp}"):
        return ("partition(python): mount root failed", "")
    os.makedirs(f"{root_mp}/boot/efi", exist_ok=True)
    if not run_cmd(f"mount {efi_dev} {root_mp}/boot/efi"):
        return ("partition(python): mount ESP failed", "")

    efi_uuid = get_uuid(efi_dev)
    root_uuid = get_uuid(root_dev)

    gs.insert("rootMountPoint", root_mp)
    gs.insert("firmwareType", "efi")
    gs.insert("bootLoader", {"installPath": dev})

    partitions = [
        {
            "device": root_dev,
            "mountPoint": "/",
            "fs": "ext4",
            "uuid": root_uuid,
            "options": "defaults,noatime",
            "claimed": True,
            "active": True,
        },
        {
            "device": efi_dev,
            "mountPoint": "/boot/efi",
            "fs": "fat32",
            "uuid": efi_uuid,
            "options": "umask=0077",
            "claimed": True,
            "active": True,
        },
    ]
    gs.insert("partitions", partitions)

    gs.insert("localeConf", {
        "LANG": "en_US.UTF-8",
        "LC_NUMERIC": "en_US.UTF-8",
        "LC_TIME": "en_US.UTF-8",
        "LC_MONETARY": "en_US.UTF-8",
        "LC_PAPER": "en_US.UTF-8",
        "LC_NAME": "en_US.UTF-8",
        "LC_ADDRESS": "en_US.UTF-8",
        "LC_TELEPHONE": "en_US.UTF-8",
        "LC_MEASUREMENT": "en_US.UTF-8",
        "LC_IDENTIFICATION": "en_US.UTF-8",
    })
    gs.insert("mountOptionsList", [
        {"mountpoint": "/", "option_string": "defaults,noatime"},
        {"mountpoint": "/boot/efi", "option_string": "umask=0077"},
    ])
    gs.insert("partitionChoices", {"erase": True})

    libcalamares.utils.debug(
        f"partition(python): done. rootMountPoint={root_mp} "
        f"root_uuid={root_uuid} efi_uuid={efi_uuid} firmwareType=efi"
    )
    return None

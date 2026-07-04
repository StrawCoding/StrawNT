#!/usr/bin/env python3
"""
mount — Calamares Python job that sets up chroot bind mounts for the target.
Replaces the upstream mount module which crashes trying to makedirs inside sysfs.
Our partition module already mounted the target root and EFI partitions;
this module adds the bind mounts needed for chroot operations.
"""
import os
import subprocess
import libcalamares


def run_cmd(cmd):
    libcalamares.utils.debug(f"mount(python): {cmd}")
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode != 0:
        libcalamares.utils.warning(f"mount cmd failed: {cmd}\nstderr: {r.stderr}")
    return r.returncode == 0


def run():
    gs = libcalamares.globalstorage
    root_mp = gs.value("rootMountPoint")

    if not root_mp:
        return ("mount(python): rootMountPoint not set in GlobalStorage", "")

    libcalamares.utils.debug(f"mount(python): setting up bind mounts at {root_mp}")

    bind_mounts = [
        ("/dev", os.path.join(root_mp, "dev")),
        ("/proc", os.path.join(root_mp, "proc")),
        ("/run", os.path.join(root_mp, "run")),
    ]

    # Create target dirs and do bind mounts
    for src, dst in bind_mounts:
        os.makedirs(dst, exist_ok=True)
        if not run_cmd(f"mount --bind {src} {dst}"):
            libcalamares.utils.warning(f"mount(python): bind mount {src} -> {dst} failed")

    # Mount sysfs separately (not bind, to avoid issues)
    sys_dst = os.path.join(root_mp, "sys")
    os.makedirs(sys_dst, exist_ok=True)
    run_cmd(f"mount -t sysfs sysfs {sys_dst}")

    # EFI vars if available on host
    efi_dst = os.path.join(root_mp, "sys", "firmware", "efi", "efivars")
    if os.path.isdir("/sys/firmware/efi/efivars"):
        # Don't makedirs inside sysfs — just mount if the path exists after sysfs mount
        if os.path.isdir(efi_dst):
            run_cmd(f"mount --bind /sys/firmware/efi/efivars {efi_dst}")

    # /run/udev bind mount for device discovery
    udev_dst = os.path.join(root_mp, "run", "udev")
    if os.path.isdir(udev_dst):
        run_cmd(f"mount --bind /run/udev {udev_dst}")

    # /run/systemd/resolve for DNS in chroot
    resolve_dst = os.path.join(root_mp, "run", "systemd", "resolve")
    if os.path.isdir("/run/systemd/resolve"):
        os.makedirs(resolve_dst, exist_ok=True)
        run_cmd(f"mount --bind /run/systemd/resolve {resolve_dst}")

    libcalamares.utils.debug(f"mount(python): bind mounts complete at {root_mp}")
    return None

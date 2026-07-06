"""StrawWU initramfs hooks — strip live casper initramfs; enforce disk BOOT=local."""
from __future__ import annotations

import glob
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG_PATH = Path("/var/log/strawwu/initramfs-hooks.log")
MARKER_PATH = Path("/var/lib/strawwu/setup/initramfs-hooks.ok")
MANIFEST_PATH = Path(
    "/usr/share/strawwu/initramfs-hooks/initramfs-hooks-manifest.yaml"
)
DISK_BOOT_CONF = Path("/etc/initramfs-tools/conf.d/strawwu-disk-boot")
INITRAMFS_CONF = Path("/etc/initramfs-tools/initramfs.conf")
ERROR_CODE = "SWU-IN-005"
PKG_VERSION = "0.5.0.0-target"

HOOK_FILES = [
    Path("/usr/share/initramfs-tools/hooks/casper"),
    Path("/usr/share/initramfs-tools/hooks/live-boot"),
]

CONF_FILES = [
    Path("/usr/share/initramfs-tools/conf.d/casper"),
    Path("/etc/initramfs-tools/conf.d/casper"),
]

SCRIPT_GLOBS = [
    "/usr/share/initramfs-tools/scripts/casper*",
    "/usr/share/initramfs-tools/scripts/live*",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def log_event(level: str, message: str, **fields: Any) -> None:
    entry = {"ts": utc_now(), "level": level, "msg": message, **fields}
    line = json.dumps(entry, ensure_ascii=False)
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        print(line, file=sys.stderr)


def run_cmd(args: list[str], *, dry_run: bool = False) -> subprocess.CompletedProcess[str]:
    log_event("info", "exec", cmd=args, dry_run=dry_run)
    if dry_run:
        return subprocess.CompletedProcess(args, 0, "", "")
    return subprocess.run(args, capture_output=True, text=True, check=False)


def initd_cmd(*args: str, dry_run: bool = False) -> int:
    proc = run_cmd(["/usr/bin/strawwu-initd", *args], dry_run=dry_run)
    if proc.returncode != 0 and not dry_run:
        log_event(
            "error",
            "initd failed",
            args=list(args),
            stderr=proc.stderr.strip(),
            code=ERROR_CODE,
        )
    return proc.returncode


def set_lifecycle(phase: str, value: str, *, dry_run: bool = False) -> bool:
    return initd_cmd("set", f"lifecycle.{phase}", value, dry_run=dry_run) == 0


def _remove_path(path: Path, *, dry_run: bool = False) -> bool:
    if not path.exists() and not path.is_symlink():
        return False
    log_event("info", "remove live initramfs artifact", path=str(path), dry_run=dry_run)
    if dry_run:
        return True
    if path.is_dir():
        shutil.rmtree(path, ignore_errors=True)
    else:
        path.unlink(missing_ok=True)
    return True


def strip_live_initramfs_hooks(*, dry_run: bool = False) -> int:
    removed = 0
    for path in HOOK_FILES + CONF_FILES:
        if _remove_path(path, dry_run=dry_run):
            removed += 1
    for pattern in SCRIPT_GLOBS:
        for match in sorted(glob.glob(pattern)):
            if _remove_path(Path(match), dry_run=dry_run):
                removed += 1
    log_event("info", "strip live initramfs hooks complete", removed=removed)
    return removed


def install_disk_boot_conf(*, dry_run: bool = False) -> None:
    content = (
        "# StrawWU installed target — disk boot (not live casper ISO).\n"
        "# Managed by strawwu-initramfs-hooks (W8-S4).\n"
        "BOOT=local\n"
    )
    if dry_run:
        log_event("info", "would write disk-boot conf", path=str(DISK_BOOT_CONF))
        return
    DISK_BOOT_CONF.parent.mkdir(parents=True, exist_ok=True)
    DISK_BOOT_CONF.write_text(content, encoding="utf-8")
    log_event("info", "disk-boot conf installed", path=str(DISK_BOOT_CONF))


def configure_initramfs_conf(*, dry_run: bool = False) -> None:
    if not INITRAMFS_CONF.is_file():
        log_event("info", "initramfs.conf absent; skip BOOT=local sed")
        return
    if dry_run:
        log_event("info", "would set BOOT=local in initramfs.conf")
        return
    text = INITRAMFS_CONF.read_text(encoding="utf-8")
    if "BOOT=local" in text:
        log_event("info", "initramfs.conf already BOOT=local")
        return
    if "BOOT=" in text:
        text = "\n".join(
            "BOOT=local" if line.startswith("BOOT=") else line
            for line in text.splitlines()
        )
    else:
        text = text.rstrip() + "\nBOOT=local\n"
    INITRAMFS_CONF.write_text(text, encoding="utf-8")
    log_event("info", "initramfs.conf BOOT=local")


def regenerate_initramfs(*, dry_run: bool = False) -> bool:
    if dry_run:
        log_event("info", "would run update-initramfs -u")
        return True
    if not shutil.which("update-initramfs"):
        log_event("warn", "update-initramfs not found; skip regeneration")
        return True
    proc = run_cmd(["update-initramfs", "-u"], dry_run=False)
    if proc.returncode != 0:
        log_event("warn", "update-initramfs failed", stderr=proc.stderr.strip())
        return False
    log_event("info", "update-initramfs -u complete")
    return True


def write_marker(*, dry_run: bool = False) -> None:
    if dry_run:
        return
    MARKER_PATH.parent.mkdir(parents=True, exist_ok=True)
    MARKER_PATH.write_text(f"ok {utc_now()}\n", encoding="utf-8")


def run_initramfs_hooks(
    *,
    skip_initramfs: bool = False,
    dry_run: bool = False,
) -> int:
    log_event(
        "info",
        "initramfs-hooks start",
        dry_run=dry_run,
        skip_initramfs=skip_initramfs,
    )

    if not set_lifecycle("initramfs_hooks", "running", dry_run=dry_run):
        set_lifecycle("initramfs_hooks", "failed", dry_run=dry_run)
        return 1

    strip_live_initramfs_hooks(dry_run=dry_run)
    install_disk_boot_conf(dry_run=dry_run)
    configure_initramfs_conf(dry_run=dry_run)

    if not skip_initramfs and not regenerate_initramfs(dry_run=dry_run):
        set_lifecycle("initramfs_hooks", "failed", dry_run=dry_run)
        return 1

    write_marker(dry_run=dry_run)
    if not set_lifecycle("initramfs_hooks", "done", dry_run=dry_run):
        return 1

    log_event("info", "initramfs-hooks complete")
    return 0


def cmd_version() -> int:
    print(f"strawwu-initramfs-hooks {PKG_VERSION} (log: {LOG_PATH})")
    return 0

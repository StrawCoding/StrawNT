"""StrawWU target identity — Calamares chroot GRUB/Plymouth/post-install branding."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG_PATH = Path("/var/log/strawwu/target-identity.log")
MARKER_PATH = Path("/var/lib/strawwu/setup/target-identity.ok")
MANIFEST_PATH = Path("/usr/share/strawwu/target-identity/target-identity-manifest.yaml")
GRUB_DROPIN = Path("/etc/default/grub.d/99-strawwu-identity.cfg")
GRUB_MAIN = Path("/etc/default/grub")
PLYMOUTH_THEME = Path("/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth")
ERROR_CODE = "SWU-IN-003"
PKG_VERSION = "0.4.1.28"


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


def configure_grub_dropin(*, dry_run: bool = False) -> bool:
    content = 'GRUB_DISTRIBUTOR="StrawWU"\n'
    shipped = Path("/usr/share/strawwu/target-identity/grub-dropin.cfg")
    if shipped.is_file():
        content = shipped.read_text(encoding="utf-8")
    elif GRUB_DROPIN.is_file():
        content = GRUB_DROPIN.read_text(encoding="utf-8")

    if dry_run:
        log_event("info", "would write grub drop-in", path=str(GRUB_DROPIN))
        return True

    GRUB_DROPIN.parent.mkdir(parents=True, exist_ok=True)
    GRUB_DROPIN.write_text(content, encoding="utf-8")
    log_event("info", "grub drop-in written", path=str(GRUB_DROPIN))

    if GRUB_MAIN.is_file():
        text = GRUB_MAIN.read_text(encoding="utf-8")
        if re.search(r"^GRUB_DISTRIBUTOR=", text, flags=re.MULTILINE):
            text = re.sub(
                r'^GRUB_DISTRIBUTOR=.*',
                'GRUB_DISTRIBUTOR="StrawWU"',
                text,
                flags=re.MULTILINE,
            )
        else:
            text = text.rstrip() + '\nGRUB_DISTRIBUTOR="StrawWU"\n'
        GRUB_MAIN.write_text(text, encoding="utf-8")
        log_event("info", "grub main patched", path=str(GRUB_MAIN))
    return True


def configure_plymouth(*, dry_run: bool = False) -> bool:
    if not PLYMOUTH_THEME.is_file():
        log_event("warn", "plymouth theme missing", path=str(PLYMOUTH_THEME))
        return False

    alt_install = [
        "update-alternatives",
        "--install",
        "/usr/share/plymouth/themes/default.plymouth",
        "default.plymouth",
        "/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth",
        "200",
    ]
    alt_set = [
        "update-alternatives",
        "--set",
        "default.plymouth",
        "/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth",
    ]
    for cmd in (alt_install, alt_set):
        proc = run_cmd(cmd, dry_run=dry_run)
        if proc.returncode != 0 and not dry_run:
            log_event("warn", "update-alternatives plymouth", stderr=proc.stderr.strip())

    if not dry_run:
        run_cmd(["plymouth-set-default-theme", "strawwu-boot"], dry_run=False)

    plymouth_conf = Path("/etc/plymouth/plymouthd.conf")
    if plymouth_conf.is_file() and not dry_run:
        text = plymouth_conf.read_text(encoding="utf-8")
        if not re.search(r"^Theme=strawwu-boot", text, flags=re.MULTILINE):
            if re.search(r"^Theme=", text, flags=re.MULTILINE):
                text = re.sub(r"^Theme=.*", "Theme=strawwu-boot", text, flags=re.MULTILINE)
            else:
                text = text.rstrip() + "\nTheme=strawwu-boot\n"
            plymouth_conf.write_text(text, encoding="utf-8")
            log_event("info", "plymouthd.conf theme set")

    log_event("info", "plymouth theme configured", theme="strawwu-boot")
    return True


def patch_user_visible_strings(*, dry_run: bool = False) -> None:
    targets = [
        Path("/etc/issue"),
        Path("/etc/issue.net"),
        Path("/etc/motd"),
    ]
    for path in targets:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        if "Ubuntu" not in text:
            continue
        new_text = text.replace("Ubuntu", "StrawWU")
        if dry_run:
            log_event("info", "would patch user-visible string", path=str(path))
        else:
            path.write_text(new_text, encoding="utf-8")
            log_event("info", "patched user-visible string", path=str(path))


def regenerate_boot_artifacts(*, skip_initramfs: bool = False, dry_run: bool = False) -> bool:
    ok = True
    if dry_run:
        log_event("info", "would run update-grub")
        if not skip_initramfs:
            log_event("info", "would run update-initramfs -u")
        return True

    if run_cmd(["update-grub"], dry_run=False).returncode != 0:
        if run_cmd(["grub-mkconfig", "-o", "/boot/grub/grub.cfg"], dry_run=False).returncode != 0:
            log_event("error", "grub config refresh failed", code=ERROR_CODE)
            ok = False

    if not skip_initramfs:
        proc = run_cmd(["update-initramfs", "-u"], dry_run=False)
        if proc.returncode != 0:
            log_event("warn", "update-initramfs failed", stderr=proc.stderr.strip())

    return ok


def write_marker(*, dry_run: bool = False) -> None:
    if dry_run:
        log_event("info", "would write marker", path=str(MARKER_PATH))
        return
    MARKER_PATH.parent.mkdir(parents=True, exist_ok=True)
    MARKER_PATH.write_text(f"ok {utc_now()}\n", encoding="utf-8")


def run_target_identity(
    *,
    skip_initramfs: bool = False,
    dry_run: bool = False,
) -> int:
    log_event("info", "target-identity start", dry_run=dry_run, skip_initramfs=skip_initramfs)

    if not set_lifecycle("target_identity", "running", dry_run=dry_run):
        set_lifecycle("target_identity", "failed", dry_run=dry_run)
        return 1

    grub_ok = configure_grub_dropin(dry_run=dry_run)
    plymouth_ok = configure_plymouth(dry_run=dry_run)
    patch_user_visible_strings(dry_run=dry_run)

    if not grub_ok:
        set_lifecycle("target_identity", "failed", dry_run=dry_run)
        return 1

    if not regenerate_boot_artifacts(skip_initramfs=skip_initramfs, dry_run=dry_run):
        set_lifecycle("target_identity", "failed", dry_run=dry_run)
        return 1

    if not plymouth_ok:
        log_event("warn", "plymouth theme not fully configured")

    write_marker(dry_run=dry_run)

    if not set_lifecycle("target_identity", "done", dry_run=dry_run):
        return 1

    log_event("info", "target-identity complete")
    return 0


def cmd_version() -> int:
    print(f"strawwu-target-identity {PKG_VERSION} (log: {LOG_PATH})")
    return 0

"""StrawWU disable upstream init — cloud-init/gnome-initial-setup off + meta purge."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG_PATH = Path("/var/log/strawwu/disable-upstream-init.log")
MARKER_PATH = Path("/var/lib/strawwu/setup/upstream-init-disabled.ok")
MANIFEST_PATH = Path(
    "/usr/share/strawwu/disable-upstream-init/disable-upstream-init-manifest.yaml"
)
CLOUD_INIT_DISABLED = Path("/etc/cloud/cloud-init.disabled")
DCONF_KEYFILE = Path("/etc/dconf/db/local.d/01-strawwu-no-gnome-initial-setup")
ERROR_CODE = "SWU-IN-004"
PKG_VERSION = "0.4.1.29"

CLOUD_INIT_UNITS = [
    "cloud-init.service",
    "cloud-init-local.service",
    "cloud-init-hotplugd.service",
    "cloud-config.service",
    "cloud-final.service",
    "cloud-init.target",
]

GNOME_INITIAL_SETUP_UNITS = [
    "gnome-initial-setup.service",
    "gnome-initial-setup-first-login.service",
]

UPSTREAM_METAS = [
    "ubuntu-desktop",
    "ubuntu-desktop-minimal",
    "ubuntu-session",
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


def mask_systemd_unit(unit: str, *, dry_run: bool = False) -> None:
    link = Path(f"/etc/systemd/system/{unit}")
    if dry_run:
        log_event("info", "would mask systemd unit", unit=unit, path=str(link))
        return
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink() and link.resolve() == Path("/dev/null"):
        log_event("info", "systemd unit already masked", unit=unit)
        return
    if link.exists() or link.is_symlink():
        link.unlink(missing_ok=True)
    link.symlink_to("/dev/null")
    log_event("info", "masked systemd unit", unit=unit)


def disable_cloud_init(*, dry_run: bool = False) -> bool:
    if dry_run:
        log_event("info", "would disable cloud-init", marker=str(CLOUD_INIT_DISABLED))
    else:
        CLOUD_INIT_DISABLED.parent.mkdir(parents=True, exist_ok=True)
        CLOUD_INIT_DISABLED.touch(exist_ok=True)
        log_event("info", "cloud-init disabled marker written", path=str(CLOUD_INIT_DISABLED))

    for unit in CLOUD_INIT_UNITS:
        mask_systemd_unit(unit, dry_run=dry_run)
    return True


def disable_gnome_initial_setup(*, dry_run: bool = False) -> bool:
    shipped = Path(
        "/usr/share/strawwu/disable-upstream-init/dconf-initial-setup-keyfile"
    )
    if not DCONF_KEYFILE.is_file() and shipped.is_file() and not dry_run:
        DCONF_KEYFILE.parent.mkdir(parents=True, exist_ok=True)
        DCONF_KEYFILE.write_text(shipped.read_text(encoding="utf-8"), encoding="utf-8")

    if dry_run:
        log_event("info", "would configure gnome-initial-setup skip", dconf=str(DCONF_KEYFILE))
    elif DCONF_KEYFILE.is_file():
        log_event("info", "gnome-initial-setup dconf keyfile present", path=str(DCONF_KEYFILE))

    for unit in GNOME_INITIAL_SETUP_UNITS:
        mask_systemd_unit(unit, dry_run=dry_run)

    if not dry_run and DCONF_KEYFILE.is_file():
        proc = run_cmd(["dconf", "update"], dry_run=False)
        if proc.returncode != 0:
            log_event("warn", "dconf update failed", stderr=proc.stderr.strip())
    elif dry_run:
        log_event("info", "would run dconf update")

    autostart = Path("/etc/xdg/autostart/gnome-initial-setup-first-login.desktop")
    if autostart.is_file() and not dry_run:
        hidden = Path("/etc/xdg/autostart/gnome-initial-setup-first-login.desktop.disabled")
        if not hidden.exists():
            autostart.rename(hidden)
            log_event("info", "disabled gnome-initial-setup autostart")

    return True


def _dpkg_installed(package: str) -> bool:
    proc = subprocess.run(
        ["dpkg-query", "-W", "-f=${Status}", package],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode == 0 and "ok installed" in proc.stdout


def purge_upstream_metas(*, dry_run: bool = False) -> bool:
    ok = True
    for pkg in UPSTREAM_METAS:
        if not _dpkg_installed(pkg):
            log_event("info", "upstream meta not installed", package=pkg)
            continue
        cmd = ["dpkg", "--purge", "--force-depends", pkg]
        proc = run_cmd(cmd, dry_run=dry_run)
        if proc.returncode != 0 and not dry_run:
            proc = run_cmd(["apt-get", "remove", "-y", "--purge", pkg], dry_run=False)
            if proc.returncode != 0:
                log_event(
                    "error",
                    "failed to purge upstream meta",
                    package=pkg,
                    stderr=proc.stderr.strip(),
                    code=ERROR_CODE,
                )
                ok = False
                continue
        log_event("info", "purged upstream meta", package=pkg)
    return ok or dry_run


def write_marker(*, dry_run: bool = False) -> None:
    if dry_run:
        log_event("info", "would write marker", path=str(MARKER_PATH))
        return
    MARKER_PATH.parent.mkdir(parents=True, exist_ok=True)
    MARKER_PATH.write_text(f"ok {utc_now()}\n", encoding="utf-8")


def run_disable_upstream_init(
    *,
    skip_meta_purge: bool = False,
    dry_run: bool = False,
) -> int:
    log_event(
        "info",
        "disable-upstream-init start",
        dry_run=dry_run,
        skip_meta_purge=skip_meta_purge,
    )

    if not set_lifecycle("upstream_init_disabled", "running", dry_run=dry_run):
        set_lifecycle("upstream_init_disabled", "failed", dry_run=dry_run)
        return 1

    if not disable_cloud_init(dry_run=dry_run):
        set_lifecycle("upstream_init_disabled", "failed", dry_run=dry_run)
        return 1

    if not disable_gnome_initial_setup(dry_run=dry_run):
        set_lifecycle("upstream_init_disabled", "failed", dry_run=dry_run)
        return 1

    if not skip_meta_purge:
        if not purge_upstream_metas(dry_run=dry_run):
            set_lifecycle("upstream_init_disabled", "failed", dry_run=dry_run)
            return 1
    else:
        log_event("info", "skipping upstream meta purge")

    write_marker(dry_run=dry_run)

    if not set_lifecycle("upstream_init_disabled", "done", dry_run=dry_run):
        return 1

    log_event("info", "disable-upstream-init complete")
    return 0


def cmd_version() -> int:
    print(f"strawwu-disable-upstream-init {PKG_VERSION} (log: {LOG_PATH})")
    return 0

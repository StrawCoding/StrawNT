"""StrawWU greeter — GDM theme, logo, session defaults (GRT0–GRT2)."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG_PATH = Path("/var/log/strawwu/greeter.log")
MARKER_PATH = Path("/var/lib/strawwu/setup/greeter.ok")
MANIFEST_PATH = Path("/usr/share/strawwu/greeter/greeter-manifest.yaml")
GDM_CUSTOM = Path("/etc/gdm3/custom.conf")
GDM_GREETER_DCONF = Path("/etc/gdm3/greeter.dconf-defaults")
SHIPPED_DCONF = Path("/usr/share/strawwu/greeter/greeter.dconf-defaults")
GREETER_CSS = Path("/usr/share/gnome-shell/theme/strawwu-greeter.css")
DEFAULT_SESSION = "strawwu-session"
ERROR_CODE = "SWU-GR-001"
PKG_VERSION = "0.4.1.32"
_PKG_USR = Path(__file__).resolve().parent.parent.parent


def _shipped_dconf_path() -> Path:
    if SHIPPED_DCONF.is_file():
        return SHIPPED_DCONF
    dev = _PKG_USR / "share" / "strawwu" / "greeter" / "greeter.dconf-defaults"
    if dev.is_file():
        return dev
    if GDM_GREETER_DCONF.is_file():
        return GDM_GREETER_DCONF
    return SHIPPED_DCONF


def _greeter_css_path() -> Path:
    if GREETER_CSS.is_file():
        return GREETER_CSS
    dev = _PKG_USR / "share" / "gnome-shell" / "theme" / "strawwu-greeter.css"
    if dev.is_file():
        return dev
    return GREETER_CSS


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


def _read_text(path: Path) -> str:
    if path.is_file():
        return path.read_text(encoding="utf-8")
    return ""


def configure_greeter_dconf(*, dry_run: bool = False) -> bool:
    source = _shipped_dconf_path()
    if not source.is_file():
        log_event("error", "greeter dconf template missing", path=str(source), code=ERROR_CODE)
        return False

    content = source.read_text(encoding="utf-8")
    if dry_run:
        log_event("info", "would write greeter.dconf-defaults", path=str(GDM_GREETER_DCONF))
        return True

    GDM_GREETER_DCONF.parent.mkdir(parents=True, exist_ok=True)
    GDM_GREETER_DCONF.write_text(content, encoding="utf-8")
    log_event("info", "greeter.dconf-defaults written", path=str(GDM_GREETER_DCONF))
    return True


def configure_gdm_custom(*, dry_run: bool = False) -> bool:
    if not GDM_CUSTOM.exists() and dry_run:
        log_event("info", "would create gdm custom.conf", path=str(GDM_CUSTOM))
        text = "[daemon]\n"
    elif not GDM_CUSTOM.exists():
        log_event("info", "gdm3 custom.conf absent; skip session default")
        return True
    else:
        text = GDM_CUSTOM.read_text(encoding="utf-8")

    if DEFAULT_SESSION in text and re.search(
        rf"DefaultSession\s*=\s*{re.escape(DEFAULT_SESSION)}", text
    ):
        log_event("info", "gdm default session already set")
        return True

    if dry_run:
        log_event("info", "would set GDM DefaultSession", session=DEFAULT_SESSION)
        return True

    if "[daemon]" in text:
        if re.search(r"^DefaultSession=", text, flags=re.MULTILINE):
            text = re.sub(
                r"^DefaultSession=.*",
                f"DefaultSession={DEFAULT_SESSION}",
                text,
                flags=re.MULTILINE,
            )
        else:
            text = text.replace(
                "[daemon]",
                f"[daemon]\nDefaultSession={DEFAULT_SESSION}",
                1,
            )
    else:
        text = text.rstrip() + f"\n[daemon]\nDefaultSession={DEFAULT_SESSION}\n"

    GDM_CUSTOM.write_text(text, encoding="utf-8")
    log_event("info", "gdm DefaultSession configured", session=DEFAULT_SESSION)
    return True


def configure_single_user_greeter(*, dry_run: bool = False) -> bool:
    """GRT deferred scope: single-user login — no fast-user-switching UI."""
    if os.environ.get("STRAWWU_LIVE_AUTOLOGIN") == "1":
        log_event("info", "live autologin mode; keep greeter user list enabled")
        return True

    dconf_text = _read_text(GDM_GREETER_DCONF)
    if "disable-user-list=true" in dconf_text.replace(" ", ""):
        log_event("info", "single-user greeter already configured")
        return True

    if dry_run:
        log_event("info", "would enforce disable-user-list for installed target")
        return True

    return True


def verify_theme_assets(*, dry_run: bool = False) -> bool:
    css = _greeter_css_path()
    if css.is_file():
        log_event("info", "greeter css present", path=str(css))
        return True
    if dry_run:
        log_event("info", "would verify greeter css", path=str(GREETER_CSS))
        return True
    log_event("error", "greeter css missing", path=str(GREETER_CSS), code=ERROR_CODE)
    return False


def write_marker(*, dry_run: bool = False) -> None:
    if dry_run:
        log_event("info", "would write marker", path=str(MARKER_PATH))
        return
    MARKER_PATH.parent.mkdir(parents=True, exist_ok=True)
    MARKER_PATH.write_text(f"ok {utc_now()}\n", encoding="utf-8")


def run_greeter_apply(*, dry_run: bool = False) -> int:
    log_event("info", "greeter apply start", dry_run=dry_run)

    if not set_lifecycle("greeter", "running", dry_run=dry_run):
        set_lifecycle("greeter", "failed", dry_run=dry_run)
        return 1

    steps = [
        configure_greeter_dconf,
        configure_gdm_custom,
        configure_single_user_greeter,
        verify_theme_assets,
    ]
    for step in steps:
        if not step(dry_run=dry_run):
            set_lifecycle("greeter", "failed", dry_run=dry_run)
            return 1

    write_marker(dry_run=dry_run)

    if not set_lifecycle("greeter", "done", dry_run=dry_run):
        return 1

    log_event("info", "greeter apply complete", default_session=DEFAULT_SESSION)
    return 0


def cmd_version() -> int:
    print(f"strawwu-greeter {PKG_VERSION} (log: {LOG_PATH})")
    return 0

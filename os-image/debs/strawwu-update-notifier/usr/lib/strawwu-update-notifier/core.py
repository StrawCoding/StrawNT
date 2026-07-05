"""StrawWU update notifier — logging, copy, apt check, notifications."""
from __future__ import annotations

import json
import locale
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG_PATH = Path("/var/log/strawwu/update.log")
COPY_PATH = Path("/usr/share/strawwu/update-notifier/backup-copy.yaml")
STATE_PATH = Path("/var/lib/strawwu/update-notifier-state")
ERROR_ROLLBACK = "SWU-UP-005"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log_event(level: str, message: str, **fields: Any) -> None:
    entry = {"ts": utc_now(), "level": level, "msg": message, **fields}
    line = json.dumps(entry, ensure_ascii=False)
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        print(line, file=sys.stderr)


def _parse_simple_yaml(text: str) -> dict[str, Any]:
    """Minimal YAML parser for backup-copy.yaml (nested maps + block scalars)."""
    root: dict[str, Any] = {}
    lines = text.splitlines()
    i = 0

    def leading_spaces(s: str) -> int:
        return len(s) - len(s.lstrip(" "))

    while i < len(lines):
        raw = lines[i]
        i += 1
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if ":" not in raw:
            continue

        key, _, rest = raw.partition(":")
        key = key.strip()
        value = rest.strip()
        depth = leading_spaces(raw)

        if depth != 0:
            continue

        if value in ("", "|"):
            section: dict[str, Any] = {}
            root[key] = section
            while i < len(lines):
                nxt = lines[i]
                if not nxt.strip():
                    i += 1
                    continue
                if leading_spaces(nxt) < 2:
                    break
                sub_key, _, sub_rest = nxt.strip().partition(":")
                sub_key = sub_key.strip()
                sub_val = sub_rest.strip()
                i += 1
                if sub_val == "|":
                    block: list[str] = []
                    while i < len(lines):
                        blk = lines[i]
                        if not blk.strip():
                            block.append("")
                            i += 1
                            continue
                        if leading_spaces(blk) < 4:
                            break
                        block.append(blk[4:])
                        i += 1
                    section[sub_key] = "\n".join(block).rstrip("\n")
                elif sub_val.startswith('"') and sub_val.endswith('"'):
                    section[sub_key] = sub_val[1:-1]
                else:
                    section[sub_key] = sub_val
        elif value.startswith('"') and value.endswith('"'):
            root[key] = value[1:-1]
        else:
            root[key] = value

    return root


def _repo_copy_path() -> Path:
    # .../usr/lib/strawwu-update-notifier/core.py → .../usr/share/strawwu/...
    usr_root = Path(__file__).resolve().parents[2]
    return usr_root / "share/strawwu/update-notifier/backup-copy.yaml"


def load_copy() -> dict[str, Any]:
    path = COPY_PATH if COPY_PATH.is_file() else _repo_copy_path()
    return _parse_simple_yaml(path.read_text(encoding="utf-8"))


def pick_locale(copy: dict[str, Any]) -> str:
    lang = os.environ.get("LANG", "") or (locale.getdefaultlocale()[0] or "en")
    if lang.startswith("zh"):
        return "zh_TW"
    return "en"


def locale_strings(copy: dict[str, Any], loc: str | None = None) -> dict[str, str]:
    loc = loc or pick_locale(copy)
    block = copy.get(loc) or copy.get("en") or {}
    return {str(k): str(v) for k, v in block.items() if isinstance(v, str)}


def run_apt_update() -> bool:
    try:
        subprocess.run(
            ["apt-get", "update", "-qq"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=120,
        )
        return True
    except (OSError, subprocess.TimeoutExpired):
        return False


def count_upgradable() -> int:
    try:
        proc = subprocess.run(
            [
                "apt-get",
                "-s",
                "-o",
                "Debug::NoLocking=true",
                "dist-upgrade",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
        text = proc.stdout + proc.stderr
        return len(re.findall(r"^Inst .+ \[(.+)\]", text, re.MULTILINE))
    except (OSError, subprocess.TimeoutExpired):
        return 0


def check_updates(*, refresh: bool = True) -> int:
    if refresh:
        run_apt_update()
    count = count_upgradable()
    log_event("info", "update check", upgradable=count)
    return count


def notify_desktop(title: str, body: str) -> bool:
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        log_event("info", "skip notify (headless)", title=title)
        return False
    try:
        subprocess.run(
            ["notify-send", "--app-name=StrawWU", title, body],
            check=False,
            timeout=10,
        )
        log_event("info", "desktop notification", title=title)
        return True
    except (OSError, subprocess.TimeoutExpired):
        return False


def show_backup_reminder() -> int:
    copy = load_copy()
    strings = locale_strings(copy)
    title = strings.get("backup_title", "Back up before upgrading")
    body = strings.get("backup_body", "Back up important files before upgrading.")
    confirm = strings.get("backup_confirm", "Continue")

    log_event("info", "backup reminder shown", locale=pick_locale(copy))

    if os.environ.get("STRAWWU_UPDATE_NOTIFIER_DRY_RUN") == "1":
        print(f"[dry-run] {title}\n{body}")
        return 0

    display = os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")
    if display and _command_exists("zenity"):
        try:
            subprocess.run(
                [
                    "zenity",
                    "--info",
                    "--title",
                    title,
                    "--text",
                    body,
                    "--ok-label",
                    confirm,
                    "--width",
                    "420",
                ],
                check=False,
                timeout=300,
            )
            _touch_backup_reminder_state()
            return 0
        except (OSError, subprocess.TimeoutExpired):
            pass

    notify_desktop(title, body.split("\n", 1)[0].strip())
    print(f"{title}\n\n{body}", file=sys.stderr)
    _touch_backup_reminder_state()
    return 0


def _command_exists(name: str) -> bool:
    from shutil import which

    return which(name) is not None


def _touch_backup_reminder_state() -> None:
    try:
        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        STATE_PATH.write_text(f"last_backup_reminder={utc_now()}\n", encoding="utf-8")
    except OSError:
        pass


def cmd_notify(refresh: bool = True) -> int:
    count = check_updates(refresh=refresh)
    if count <= 0:
        return 1
    copy = load_copy()
    strings = locale_strings(copy)
    title = strings.get("notify_title", "StrawWU updates available")
    body = strings.get("notify_body", f"{count} updates available")
    notify_desktop(title, body)
    return 0


def cmd_pre_upgrade() -> int:
    return show_backup_reminder()


def log_rollback(reason: str) -> None:
    log_event("error", "upgrade rollback triggered", code=ERROR_ROLLBACK, reason=reason)

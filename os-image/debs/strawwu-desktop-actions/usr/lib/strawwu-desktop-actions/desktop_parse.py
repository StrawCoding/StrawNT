"""Parse .desktop files for StrawWU integration."""

from __future__ import annotations

import configparser
import re
from pathlib import Path

X_STRAWWU_APP_ID = "X-StrawWU-App-Id"
DESKTOP_ACTION_ID = "RemoveFromStrawWU"
ACTION_BLOCK = f"[Desktop Action {DESKTOP_ACTION_ID}]"


def read_desktop(path: Path) -> configparser.ConfigParser:
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str  # type: ignore[method-assign]
    parser.read(path, encoding="utf-8")
    return parser


def desktop_basename(path: Path) -> str:
    name = path.name
    if not name.endswith(".desktop"):
        return f"{name}.desktop"
    return name


def favorite_id(path: Path) -> str:
    """GNOME favorite-apps entry id (usually the .desktop basename)."""
    return desktop_basename(path)


def resolve_real_desktop(path: Path) -> Path:
    if path.is_symlink():
        target = path.resolve()
        if target.exists():
            return target
    return path


def parse_app_id(path: Path) -> str | None:
    path = resolve_real_desktop(path)
    if not path.exists() or not path.is_file():
        return None

    parser = read_desktop(path)
    if not parser.has_section("Desktop Entry"):
        return None

    section = parser["Desktop Entry"]
    app_id = section.get(X_STRAWWU_APP_ID)
    if app_id:
        return app_id.strip()

    stem = path.name.removesuffix(".desktop")
    if re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", stem.lower()):
        return stem.lower()
    return None


def display_name(path: Path) -> str:
    path = resolve_real_desktop(path)
    if path.exists():
        parser = read_desktop(path)
        if parser.has_section("Desktop Entry"):
            name = parser["Desktop Entry"].get("Name")
            if name:
                return name.strip()
    return path.name


def ensure_desktop_action(path: Path, app_id: str, protected: bool = False) -> bool:
    """Inject Desktop Action + X-StrawWU-App-Id when missing. Returns True if modified."""
    path = resolve_real_desktop(path)
    if not path.exists():
        return False

    text = path.read_text(encoding="utf-8")
    modified = False

    if f"{X_STRAWWU_APP_ID}={app_id}" not in text:
        if "[Desktop Entry]" in text:
            text = text.replace(
                "[Desktop Entry]",
                f"[Desktop Entry]\n{X_STRAWWU_APP_ID}={app_id}",
                1,
            )
            modified = True

    if ACTION_BLOCK not in text:
        action = f"""
Actions={DESKTOP_ACTION_ID};

[Desktop Action {DESKTOP_ACTION_ID}]
Name=Remove from StrawWU
Name[zh_TW]=從 StrawWU 移除
Exec=strawwu-desktop-remove --desktop %f
Icon=edit-delete
OnlyShowIn=Strawwu-session;
"""
        if protected:
            action = action.replace(
                "OnlyShowIn=Strawwu-session;",
                "OnlyShowIn=Strawwu-session;\nX-StrawWU-Protected=true",
            )
        if not text.endswith("\n"):
            text += "\n"
        text += action
        modified = True
    elif "Actions=" in text and DESKTOP_ACTION_ID not in text:
        text = re.sub(
            r"^Actions=(.*)$",
            lambda m: f"Actions={m.group(1).strip()};{DESKTOP_ACTION_ID};"
            if DESKTOP_ACTION_ID not in m.group(1)
            else m.group(0),
            text,
            count=1,
            flags=re.MULTILINE,
        )
        modified = True

    if modified:
        path.write_text(text, encoding="utf-8")
    return modified

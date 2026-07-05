"""Load desktop-actions locale strings."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

LOCALE_DIR = Path(__file__).resolve().parent.parent.parent / "share/strawwu/desktop-actions/locale"
INSTALLED_LOCALE_DIR = Path("/usr/share/strawwu/desktop-actions/locale")
DEFAULT_LOCALE = "en"


def locale_dir() -> Path:
    if INSTALLED_LOCALE_DIR.exists():
        return INSTALLED_LOCALE_DIR
    return LOCALE_DIR


def _parse_simple_yaml(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if ":" not in raw:
            continue
        key, _, value = raw.partition(":")
        data[key.strip()] = value.strip().strip('"')
    return data


def locale_name() -> str:
    override = os.environ.get("STRAWWU_DESKTOP_ACTIONS_LOCALE")
    if override:
        return override
    lang = os.environ.get("LANG", "en_US.UTF-8")
    if lang.startswith("zh"):
        return "zh_TW"
    return DEFAULT_LOCALE


def load_messages(locale: str | None = None) -> dict[str, str]:
    loc = locale or locale_name()
    base = locale_dir()
    path = base / f"desktop-actions.{loc}.yaml"
    if not path.exists():
        path = base / f"desktop-actions.{DEFAULT_LOCALE}.yaml"
    return _parse_simple_yaml(path.read_text(encoding="utf-8"))


def format_message(key: str, **kwargs: Any) -> str:
    messages = load_messages()
    template = messages.get(key, key)
    try:
        return template.format(**kwargs)
    except KeyError:
        return template

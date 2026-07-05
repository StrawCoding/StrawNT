"""Load firstboot UI strings from /usr/share/strawwu/locale/*.yaml."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

LOCALE_DIR = Path("/usr/share/strawwu/locale")
DEFAULT_LOCALE = "zh_TW"


def locale_dir() -> Path:
    override = os.environ.get("STRAWWU_LOCALE_DIR")
    if override:
        return Path(override)
    return LOCALE_DIR


def _parse_strings_yaml(text: str) -> dict[str, str]:
    root: dict[str, Any] = {}
    strings: dict[str, str] = {}
    in_strings = False

    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("strings:"):
            in_strings = True
            continue
        if in_strings:
            match = re.match(r"^\s{2}(\w+):\s+\"(.*)\"$", raw)
            if match:
                strings[match.group(1)] = match.group(2)
                continue
            if re.match(r"^\S", raw):
                in_strings = False
        if ":" in raw and not in_strings:
            key, _, rest = raw.partition(":")
            root[key.strip()] = rest.strip().strip('"')

    root["strings"] = strings
    return root


def resolve_locale_tag(locale: str) -> str:
    tag = locale.split(".")[0].replace("_", "-")
    if tag.lower().startswith("zh"):
        return "zh_TW"
    return "en"


def load_catalog(locale: str | None = None) -> dict[str, str]:
    tag = resolve_locale_tag(locale or os.environ.get("LANG", DEFAULT_LOCALE))
    path = locale_dir() / f"firstboot.{tag}.yaml"
    if not path.exists() and tag != "en":
        path = locale_dir() / "firstboot.en.yaml"
    if not path.exists():
        return {}
    data = _parse_strings_yaml(path.read_text(encoding="utf-8"))
    strings = data.get("strings", {})
    if isinstance(strings, dict):
        return {str(k): str(v) for k, v in strings.items()}
    return {}


def t(catalog: dict[str, str], key: str, **kwargs: Any) -> str:
    text = catalog.get(key, key)
    if kwargs:
        try:
            return text.format(**kwargs)
        except (KeyError, ValueError):
            return text
    return text

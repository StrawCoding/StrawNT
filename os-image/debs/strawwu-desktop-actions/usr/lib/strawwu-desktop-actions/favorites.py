"""GNOME shell favorites sync for app-registry desktop entries."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from desktop_parse import favorite_id

FAVORITES_SCHEMA = "org.gnome.shell"
FAVORITES_KEY = "favorite-apps"


def _gsettings(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["gsettings", *args],
        check=False,
        capture_output=True,
        text=True,
    )


def read_favorites() -> list[str]:
    result = _gsettings(["get", FAVORITES_SCHEMA, FAVORITES_KEY])
    if result.returncode != 0:
        return []

    raw = result.stdout.strip()
    if raw in ("@as []", "[]"):
        return []

    # gsettings returns Python-like list: ['a.desktop', 'b.desktop']
    try:
        import ast

        parsed = ast.literal_eval(raw)
        if isinstance(parsed, list):
            return [str(item) for item in parsed]
    except (SyntaxError, ValueError):
        pass
    return []


def write_favorites(entries: list[str]) -> bool:
    payload = "[" + ", ".join(f"'{item}'" for item in entries) + "]"
    result = _gsettings(["set", FAVORITES_SCHEMA, FAVORITES_KEY, payload])
    return result.returncode == 0


def remove_from_favorites(desktop_path: Path) -> bool:
    fav_id = favorite_id(desktop_path)
    current = read_favorites()
    if fav_id not in current:
        return False
    updated = [item for item in current if item != fav_id]
    return write_favorites(updated)


def add_to_favorites(desktop_path: Path) -> bool:
    fav_id = favorite_id(desktop_path)
    current = read_favorites()
    if fav_id in current:
        return False
    return write_favorites([*current, fav_id])


def sync_favorites_from_registry(registry_path: Path) -> dict[str, int]:
    """Drop favorites for removed apps; keep active registry desktop entries."""
    if not registry_path.exists():
        return {"removed": 0, "kept": 0}

    data = json.loads(registry_path.read_text(encoding="utf-8"))
    active_ids: set[str] = set()
    for app in data.get("apps", []):
        if app.get("install_state") == "removed":
            continue
        desktop = app.get("desktop_entry")
        if desktop:
            active_ids.add(Path(desktop).name)
        app_id = app.get("id")
        if app_id:
            active_ids.add(f"{app_id}.desktop")

    current = read_favorites()
    kept = [item for item in current if item in active_ids or item.startswith("org.gnome.")]
    removed = len(current) - len(kept)
    if removed:
        write_favorites(kept)
    return {"removed": removed, "kept": len(kept)}


def favorites_available() -> bool:
    if os.environ.get("STRAWWU_SKIP_FAVORITES_SYNC") == "1":
        return False
    return _gsettings(["writable", FAVORITES_SCHEMA, FAVORITES_KEY]).returncode == 0

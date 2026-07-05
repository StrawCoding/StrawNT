#!/usr/bin/env python3
"""Unit tests for strawwu-shell package files."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER = ROOT / "usr/bin/strawwu-shell"
MODE = ROOT / "usr/share/gnome-shell/modes/strawwu.json"
SHELL_YAML = ROOT / "usr/share/strawwu/shell/shell.yaml"
DOCK_YAML = ROOT / "usr/share/strawwu/shell/dock.yaml"
DISABLED = ROOT / "usr/share/strawwu/shell/disabled-extensions.json"
GSCHEMA = ROOT / "usr/share/glib-2.0/schemas/10_strawwu-shell.gschema.override"
EXT_META = ROOT / "usr/share/gnome-shell/extensions/strawwu-dock@strawwu/metadata.json"
EXT_JS = ROOT / "usr/share/gnome-shell/extensions/strawwu-dock@strawwu/extension.js"
CONTROL = ROOT / "debian/control"

FORBIDDEN_CONTROL = (
    "snapd",
    "apport",
    "whoopsie",
    "ubuntu-report",
    "ubuntu-pro-client",
)

UBUNTU_EXTENSIONS = (
    "ubuntu-dock@ubuntu.com",
    "ubuntu-appindicators@ubuntu.com",
    "ding@rastersoft.com",
)


def test_launcher_wraps_gnome_shell() -> None:
    assert LAUNCHER.is_file()
    text = LAUNCHER.read_text()
    assert "GNOME_SHELL_SESSION_MODE" in text
    assert "strawwu" in text
    assert "gnome-shell" in text
    assert "STRAWWU_SHELL=1" in text


def test_strawwu_session_mode_json() -> None:
    assert MODE.is_file()
    data = json.loads(MODE.read_text())
    assert data["parentMode"] == "user"
    assert "strawwu-dock@strawwu" in data["enabledExtensions"]
    for ext in UBUNTU_EXTENSIONS:
        assert ext not in data["enabledExtensions"]


def test_builtin_dock_extension() -> None:
    assert EXT_META.is_file()
    meta = json.loads(EXT_META.read_text())
    assert meta["uuid"] == "strawwu-dock@strawwu"
    assert "45" in meta["shell-version"]
    assert EXT_JS.is_file()
    js = EXT_JS.read_text()
    assert "strawwuDock" in js
    assert "Main.layoutManager" in js


def test_shell_manifest() -> None:
    assert SHELL_YAML.is_file()
    text = SHELL_YAML.read_text()
    assert "schema: strawwu-shell-profile/v1" in text
    assert "session_mode: strawwu" in text
    assert "public_api: false" in text


def test_dock_config_bottom() -> None:
    assert DOCK_YAML.is_file()
    text = DOCK_YAML.read_text()
    assert "position: BOTTOM" in text
    assert "icon_size: 48" in text


def test_disabled_extensions_manifest() -> None:
    assert DISABLED.is_file()
    data = json.loads(DISABLED.read_text())
    blocked = set(data["extensions"])
    for ext in UBUNTU_EXTENSIONS:
        assert ext in blocked


def test_gschema_blocks_ubuntu_extensions() -> None:
    assert GSCHEMA.is_file()
    text = GSCHEMA.read_text()
    assert "strawwu-dock@strawwu" in text
    for ext in UBUNTU_EXTENSIONS:
        assert ext in text


def test_control_depends_gnome_shell() -> None:
    assert CONTROL.is_file()
    text = CONTROL.read_text().lower()
    assert "gnome-shell" in text
    for pkg in FORBIDDEN_CONTROL:
        assert pkg not in text


def main() -> int:
    tests = [
        test_launcher_wraps_gnome_shell,
        test_strawwu_session_mode_json,
        test_builtin_dock_extension,
        test_shell_manifest,
        test_dock_config_bottom,
        test_disabled_extensions_manifest,
        test_gschema_blocks_ubuntu_extensions,
        test_control_depends_gnome_shell,
    ]
    failed = 0
    for fn in tests:
        try:
            fn()
            print(f"PASS: {fn.__name__}")
        except AssertionError as exc:
            print(f"FAIL: {fn.__name__}: {exc}", file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

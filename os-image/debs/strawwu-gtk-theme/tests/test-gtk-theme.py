#!/usr/bin/env python3
"""Unit tests for strawwu-gtk-theme package."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / "usr/share/strawwu/gtk-theme"
BRANDING = ROOT.parent.parent / "config/branding/usr/share/themes/StrawWU-Dark"
CONTROL = ROOT / "DEBIAN/control"
BUILD = ROOT / "build-deb.sh"
ACCENT = "#14B8A6"
BG = "#0A0E14"


def test_manifest_exists() -> None:
    manifest = THEME / "gtk-theme-manifest.yaml"
    assert manifest.is_file()
    text = manifest.read_text()
    assert "StrawWU-Dark" in text
    assert ACCENT in text


def test_control_depends_yaru() -> None:
    text = CONTROL.read_text()
    assert "yaru-theme-gtk" in text
    assert "yaru-theme-gnome-shell" in text


def test_build_script_exists() -> None:
    assert BUILD.is_file()


def test_branding_theme_has_teal_accent() -> None:
    gtk_css = BRANDING / "gtk-3.0/gtk.css"
    assert gtk_css.is_file()
    text = gtk_css.read_text()
    assert ACCENT in text
    assert BG in text or "#0F1318" in text


def test_branding_theme_index() -> None:
    index = BRANDING / "index.theme"
    assert index.is_file()
    text = index.read_text()
    assert "StrawWU-Dark" in text
    assert "X-Yaru-Accent-Color=#14B8A6" in text


def test_no_snap_resource_imports() -> None:
    gtk_css = BRANDING / "gtk-3.0/gtk.css"
    text = gtk_css.read_text()
    assert "resource:///com/ubuntu/themes" not in text


def test_build_script_installs_gnome_shell_theme_path() -> None:
    text = BUILD.read_text()
    assert "gnome-shell/theme/StrawWU-Dark" in text
    assert "stylesheetName resolves under /usr/share/gnome-shell/theme" in text \
        or "GNOME Shell mode stylesheetName" in text


def test_branding_gnome_shell_css_exists() -> None:
    css = BRANDING / "gnome-shell/gnome-shell.css"
    assert css.is_file()
    assert ACCENT.lower() in css.read_text().lower() or "14b8a6" in css.read_text().lower() \
        or css.stat().st_size > 1000


def main() -> int:
    tests = [
        test_manifest_exists,
        test_control_depends_yaru,
        test_build_script_exists,
        test_build_script_installs_gnome_shell_theme_path,
        test_branding_theme_has_teal_accent,
        test_branding_theme_index,
        test_branding_gnome_shell_css_exists,
        test_no_snap_resource_imports,
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

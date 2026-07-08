#!/usr/bin/env python3
"""Unit tests for strawwu-icon-theme package."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / "usr/share/strawwu/icon-theme"
CONTROL = ROOT / "DEBIAN/control"
BUILD = ROOT / "build-deb.sh"
BRANDING_LOGO = (
    ROOT.parent.parent / "config/branding/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg"
)


def test_manifest_exists() -> None:
    manifest = THEME / "icon-theme-manifest.yaml"
    assert manifest.is_file()
    text = manifest.read_text()
    assert "Yaru-prussiangreen-dark" in text
    assert "distributor-logo" in text


def test_control_depends_yaru_icon() -> None:
    text = CONTROL.read_text()
    assert "yaru-theme-icon" in text


def test_build_script_exists() -> None:
    assert BUILD.is_file()


def test_branding_distributor_logo() -> None:
    assert BRANDING_LOGO.is_file()
    text = BRANDING_LOGO.read_text()
    assert "svg" in text.lower()


def main() -> int:
    tests = [
        test_manifest_exists,
        test_control_depends_yaru_icon,
        test_build_script_exists,
        test_branding_distributor_logo,
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

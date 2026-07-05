#!/usr/bin/env python3
"""Unit tests for strawwu-session package files."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SESSION_DESKTOP = ROOT / "usr/share/xsessions/strawwu-session.desktop"
GNOME_SESSION = ROOT / "usr/share/gnome-session/sessions/strawwu.session"
LAUNCHER = ROOT / "usr/bin/strawwu-session"
AUTOSTART = ROOT / "etc/xdg/autostart/strawwu-hub-autostart.desktop"
CONTROL = ROOT / "debian/control"

FORBIDDEN_CONTROL = (
    "snapd",
    "apport",
    "whoopsie",
    "ubuntu-report",
    "ubuntu-pro-client",
)


def test_launcher_exists_and_uses_gnome_session() -> None:
    assert LAUNCHER.is_file()
    text = LAUNCHER.read_text()
    assert "gnome-session --session=strawwu" in text
    assert "GNOME_SHELL_SESSION_MODE=strawwu" in text


def test_xsession_desktop() -> None:
    assert SESSION_DESKTOP.is_file()
    text = SESSION_DESKTOP.read_text()
    assert "Name=StrawWU" in text
    assert "X-GDM-SessionRegisters=true" in text
    assert "strawwu-session" in text


def test_gnome_session_file() -> None:
    assert GNOME_SESSION.is_file()
    text = GNOME_SESSION.read_text()
    assert text.startswith("[GNOME Session]")
    assert "Name=StrawWU" in text
    assert "org.gnome.Shell" in text


def test_hub_autostart_guarded() -> None:
    assert AUTOSTART.is_file()
    text = AUTOSTART.read_text()
    assert "strawwu-hub" in text
    assert "test -x" in text


def test_control_no_forbidden_deps() -> None:
    assert CONTROL.is_file()
    text = CONTROL.read_text().lower()
    for pkg in FORBIDDEN_CONTROL:
        assert pkg not in text, f"forbidden package in control: {pkg}"


def main() -> int:
    tests = [
        test_launcher_exists_and_uses_gnome_session,
        test_xsession_desktop,
        test_gnome_session_file,
        test_hub_autostart_guarded,
        test_control_no_forbidden_deps,
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

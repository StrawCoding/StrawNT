#!/usr/bin/env python3
"""Unit tests for strawwu-live-install-ux (desktop + finished copy)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESKTOP = ROOT / "usr/share/applications/strawwu-install.desktop"
FINISHED = ROOT / "usr/share/strawwu/installer/finished-copy.yaml"
CONTROL = ROOT / "debian/control"
CALAMARES_FINISHED = (
    ROOT.parent
    / "strawwu-calamares-settings/etc/calamares/modules/finished.conf"
)


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_desktop_branding() -> None:
    text = _read(DESKTOP)
    assert "Name=Install StrawWU" in text
    assert "Name[zh_TW]=安裝 StrawWU" in text
    assert "Icon=distributor-logo" in text
    assert "calamares" in text
    assert "Ubuntu" not in text


def test_desktop_exec() -> None:
    text = _read(DESKTOP)
    assert 'Exec=sh -c "sudo -E calamares -D6"' in text
    assert "TryExec=calamares" in text
    assert "X-StrawWU-PrimaryInstaller=true" in text


def test_finished_copy_yaml() -> None:
    text = _read(FINISHED)
    assert "schema: strawwu-finished-copy/v1" in text
    assert "zh_TW:" in text
    assert "全部完成" in text
    assert "StrawWU" in text
    assert "Ubuntu" not in text


def test_control_depends() -> None:
    text = _read(CONTROL)
    assert "Package: strawwu-live-install-ux" in text
    assert "strawwu-calamares-settings" in text
    assert "calamares" in text


def test_calamares_finished_conf() -> None:
    text = _read(CALAMARES_FINISHED)
    assert "restartNowMode: user-checked" in text
    assert "notifyOnFinished: true" in text
    assert "systemctl -i reboot" in text


def main() -> int:
    tests = [
        test_desktop_branding,
        test_desktop_exec,
        test_finished_copy_yaml,
        test_control_depends,
        test_calamares_finished_conf,
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

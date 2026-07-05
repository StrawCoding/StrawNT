#!/usr/bin/env python3
"""Unit tests for strawwu-update-notifier (backup copy + package metadata)."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COPY = ROOT / "usr/share/strawwu/update-notifier/backup-copy.yaml"
CONTROL = ROOT / "debian/control"
DESKTOP = ROOT / "usr/share/applications/strawwu-update-notifier.desktop"
APT_CONF = ROOT / "etc/apt/apt.conf.d/99strawwu-update-notifier"
CLI = ROOT / "usr/bin/strawwu-update-notifier"
CORE = ROOT / "usr/lib/strawwu-update-notifier/core.py"


def _load_core():
    spec = importlib.util.spec_from_file_location("strawwu_update_notifier_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_backup_copy_schema() -> None:
    text = COPY.read_text(encoding="utf-8")
    assert "schema: strawwu-backup-copy/v1" in text
    assert "zh_TW:" in text
    assert "升級前請先備份" in text
    assert "StrawWU" in text
    assert "Ubuntu" not in text


def test_backup_copy_parser() -> None:
    mod = _load_core()
    copy = mod.load_copy()
    assert copy.get("schema") == "strawwu-backup-copy/v1"
    zh = mod.locale_strings(copy, "zh_TW")
    assert "升級前請先備份" in zh["backup_title"]
    assert "strawwu-backup" in zh["backup_body"]
    en = mod.locale_strings(copy, "en")
    assert "Back up before upgrading" in en["backup_title"]


def test_control_replaces_update_notifier() -> None:
    text = CONTROL.read_text(encoding="utf-8")
    assert "Package: strawwu-update-notifier" in text
    assert "Provides: update-notifier" in text
    assert "Conflicts: update-notifier" in text
    assert "Replaces: update-notifier" in text


def test_desktop_autostart() -> None:
    text = DESKTOP.read_text(encoding="utf-8")
    assert "strawwu-update-notifier notify" in text
    assert "X-StrawWU-UpdateNotifier=true" in text
    assert "Ubuntu" not in text


def test_apt_hook() -> None:
    text = APT_CONF.read_text(encoding="utf-8")
    assert "DPkg::Pre-Install-Pkgs" in text
    assert "apt-pre-upgrade" in text


def test_cli_dry_run_pre_upgrade() -> None:
    import os
    import subprocess

    env = os.environ.copy()
    env["STRAWWU_UPDATE_NOTIFIER_DRY_RUN"] = "1"
    proc = subprocess.run(
        [str(CLI), "pre-upgrade"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert proc.returncode == 0
    assert "Back up" in proc.stdout or "備份" in proc.stdout


def main() -> int:
    tests = [
        test_backup_copy_schema,
        test_backup_copy_parser,
        test_control_replaces_update_notifier,
        test_desktop_autostart,
        test_apt_hook,
        test_cli_dry_run_pre_upgrade,
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

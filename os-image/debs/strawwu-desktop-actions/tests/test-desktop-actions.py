#!/usr/bin/env python3
"""Unit tests for strawwu-desktop-actions."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "usr/lib/strawwu-desktop-actions"
sys.path.insert(0, str(LIB))

from desktop_parse import (  # noqa: E402
    DESKTOP_ACTION_ID,
    ensure_desktop_action,
    parse_app_id,
    X_STRAWWU_APP_ID,
)
from favorites import read_favorites, remove_from_favorites, write_favorites  # noqa: E402
from i18n import load_messages  # noqa: E402


class DesktopParseTests(unittest.TestCase):
    def test_parse_app_id_from_x_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            desktop = Path(tmp) / "demo-app.desktop"
            desktop.write_text(
                "[Desktop Entry]\n"
                "Type=Application\n"
                "Name=Demo\n"
                f"{X_STRAWWU_APP_ID}=demo-app\n",
                encoding="utf-8",
            )
            self.assertEqual(parse_app_id(desktop), "demo-app")

    def test_slug_from_basename(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            desktop = Path(tmp) / "my-game.desktop"
            desktop.write_text(
                "[Desktop Entry]\nType=Application\nName=My Game\n",
                encoding="utf-8",
            )
            self.assertEqual(parse_app_id(desktop), "my-game")

    def test_inject_desktop_action(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            desktop = Path(tmp) / "demo-app.desktop"
            desktop.write_text(
                "[Desktop Entry]\nType=Application\nName=Demo\nExec=demo\n",
                encoding="utf-8",
            )
            changed = ensure_desktop_action(desktop, "demo-app")
            self.assertTrue(changed)
            text = desktop.read_text(encoding="utf-8")
            self.assertIn(DESKTOP_ACTION_ID, text)
            self.assertIn("strawwu-desktop-remove --desktop %f", text)
            self.assertIn(f"{X_STRAWWU_APP_ID}=demo-app", text)


class I18nTests(unittest.TestCase):
    def test_zh_tw_messages(self) -> None:
        os.environ["STRAWWU_DESKTOP_ACTIONS_LOCALE"] = "zh_TW"
        messages = load_messages("zh_TW")
        self.assertIn("從 StrawWU 移除", messages["remove_label"])


class FavoritesTests(unittest.TestCase):
    def test_remove_from_favorites_mock(self) -> None:
        import favorites as fav_mod

        calls: list[list[str]] = []

        def fake_gsettings(args: list[str]) -> subprocess.CompletedProcess[str]:
            calls.append(args)
            if args[:2] == ["get", "org.gnome.shell"]:
                return subprocess.CompletedProcess(args, 0, "['demo-app.desktop', 'org.gnome.Nautilus.desktop']", "")
            if args[:2] == ["set", "org.gnome.shell"]:
                return subprocess.CompletedProcess(args, 0, "", "")
            if args[:2] == ["writable", "org.gnome.shell"]:
                return subprocess.CompletedProcess(args, 0, "true", "")
            return subprocess.CompletedProcess(args, 1, "", "")

        original = fav_mod._gsettings
        fav_mod._gsettings = fake_gsettings
        try:
            with tempfile.TemporaryDirectory() as tmp:
                desktop = Path(tmp) / "demo-app.desktop"
                desktop.write_text("[Desktop Entry]\nType=Application\nName=Demo\n", encoding="utf-8")
                removed = fav_mod.remove_from_favorites(desktop)
                self.assertTrue(removed)
                self.assertTrue(any(call[:2] == ["set", "org.gnome.shell"] for call in calls))
        finally:
            fav_mod._gsettings = original


class ManifestTests(unittest.TestCase):
    def test_manifest_exists(self) -> None:
        manifest = ROOT / "usr/share/strawwu/desktop-actions/desktop-actions-manifest.yaml"
        text = manifest.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-desktop-actions-manifest/v1", text)
        self.assertIn("remove_cli: /usr/bin/strawwu-desktop-remove", text)


class ControlTests(unittest.TestCase):
    def test_control_has_python_dep(self) -> None:
        control = (ROOT / "debian/control").read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-desktop-actions", control)
        self.assertIn("python3", control)


def main() -> int:
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for case in (DesktopParseTests, I18nTests, FavoritesTests, ManifestTests, ControlTests):
        suite.addTests(loader.loadTestsFromTestCase(case))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())

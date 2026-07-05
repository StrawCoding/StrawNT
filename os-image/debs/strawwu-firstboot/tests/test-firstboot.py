#!/usr/bin/env python3
"""Unit tests for strawwu-firstboot (no GTK required)."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/firstboot/firstboot-manifest.yaml"
CLI = ROOT / "usr/bin/strawwu-firstboot"
CORE = ROOT / "usr/lib/strawwu-firstboot/core.py"
I18N = ROOT / "usr/lib/strawwu-firstboot/i18n.py"
LOCALE_EN = ROOT / "usr/share/strawwu/locale/firstboot.en.yaml"
LOCALE_ZH = ROOT / "usr/share/strawwu/locale/firstboot.zh_TW.yaml"
INITD_CLI = ROOT.parent / "strawwu-initd/usr/bin/strawwu-initd"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


class FirstbootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.core = _load_module("strawwu_firstboot_core", CORE)
        cls.i18n = _load_module("strawwu_firstboot_i18n", I18N)

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        os.environ["STRAWWU_FIRSTBOOT_MANIFEST"] = str(MANIFEST)
        os.environ["STRAWWU_FIRSTBOOT_LOG"] = str(Path(self.tmp.name) / "firstboot.log")
        os.environ["STRAWWU_FIRSTBOOT_PREFS"] = str(Path(self.tmp.name) / "prefs.json")
        os.environ["STRAWWU_LOCALE_DIR"] = str(ROOT / "usr/share/strawwu/locale")
        os.environ["STRAWWU_SETUP_STATE"] = str(Path(self.tmp.name) / "state.json")
        os.environ["STRAWWU_INITD_LOG"] = str(Path(self.tmp.name) / "initd.log")

    def tearDown(self) -> None:
        for key in (
            "STRAWWU_FIRSTBOOT_MANIFEST",
            "STRAWWU_FIRSTBOOT_LOG",
            "STRAWWU_FIRSTBOOT_PREFS",
            "STRAWWU_LOCALE_DIR",
            "STRAWWU_SETUP_STATE",
            "STRAWWU_INITD_LOG",
            "STRAWWU_FIRSTBOOT_FORCE",
        ):
            os.environ.pop(key, None)

    def test_control_depends(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-firstboot", text)
        self.assertIn("Depends: strawwu-initd", text)
        self.assertIn("gir1.2-gtk-4.0", text)
        self.assertIn("gir1.2-adw-1", text)

    def test_manifest_six_steps(self) -> None:
        manifest = self.core.load_manifest(MANIFEST)
        errors = self.core.validate_manifest(manifest)
        self.assertEqual([], errors)
        self.assertEqual(
            ["welcome", "language", "privacy", "flathub", "desktop", "finish"],
            self.core.step_ids(manifest),
        )

    def test_locale_catalogs(self) -> None:
        en = self.i18n.load_catalog("en_US.UTF-8")
        zh = self.i18n.load_catalog("zh_TW.UTF-8")
        self.assertIn("app_title", en)
        self.assertIn("app_title", zh)
        self.assertNotEqual(en["app_title"], zh["app_title"])
        self.assertTrue(LOCALE_EN.exists())
        self.assertTrue(LOCALE_ZH.exists())

    def test_dry_run_with_initd(self) -> None:
        if not INITD_CLI.exists():
            self.skipTest("strawwu-initd CLI not present")
        subprocess.run([str(INITD_CLI), "init"], check=True)
        os.environ["STRAWWU_FIRSTBOOT_FORCE"] = "1"
        rc = self.core.run_dry_run()
        self.assertEqual(0, rc)
        log = Path(os.environ["STRAWWU_FIRSTBOOT_LOG"])
        self.assertTrue(log.exists())
        lines = [json.loads(line) for line in log.read_text().strip().splitlines()]
        self.assertGreaterEqual(len(lines), 2)
        proc = subprocess.run(
            [str(INITD_CLI), "get", "lifecycle.firstboot"],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual("pending", proc.stdout.strip())

    def test_prefs_roundtrip(self) -> None:
        prefs = self.core.default_prefs()
        prefs["bug_upload_opt_in"] = False
        prefs["analytics_opt_in"] = False
        self.core.save_prefs(prefs, dry_run=False)
        loaded = self.core.load_prefs()
        self.assertFalse(loaded["bug_upload_opt_in"])
        self.assertFalse(loaded["analytics_opt_in"])

    def test_cli_version(self) -> None:
        proc = subprocess.run(
            [str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode)
        self.assertIn("strawwu-firstboot", proc.stdout)

    def test_cli_dry_run(self) -> None:
        if not INITD_CLI.exists():
            self.skipTest("strawwu-initd CLI not present")
        subprocess.run([str(INITD_CLI), "init"], check=True)
        os.environ["STRAWWU_FIRSTBOOT_FORCE"] = "1"
        proc = subprocess.run(
            [str(CLI), "run", "--dry-run"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertIn("dry-run", proc.stdout)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Unit tests for strawwu-target-setup."""
from __future__ import annotations

import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/target-setup/target-manifest.yaml"
CLI = ROOT / "usr/bin/strawwu-target-setup"
CORE = ROOT / "usr/lib/strawwu-target-setup/core.py"


def _load_core():
    spec = importlib.util.spec_from_file_location("strawwu_target_setup_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class TargetSetupTests(unittest.TestCase):
    def test_control_depends_initd(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-target-setup", text)
        self.assertIn("Depends: strawwu-initd", text)

    def test_manifest_schema(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-target-manifest/v1", text)
        self.assertIn("strawwu-shell", text)
        self.assertIn("strawwu-session", text)
        self.assertIn("strawwu-desktop", text)
        self.assertIn("strawwu-firstboot", text)
        self.assertIn("strawwu-install-init", text)

    def test_load_manifest(self) -> None:
        mod = _load_core()
        pkgs = mod.load_manifest(MANIFEST)
        self.assertIn("strawwu-initd", pkgs)
        self.assertIn("strawwu-desktop", pkgs)
        self.assertIn("strawwu-firstboot", pkgs)
        self.assertLess(pkgs.index("strawwu-initd"), pkgs.index("strawwu-desktop"))
        self.assertLess(pkgs.index("strawwu-firstboot"), pkgs.index("strawwu-desktop"))
        self.assertLess(pkgs.index("strawwu-shell"), pkgs.index("strawwu-session"))

    def test_find_deb_file(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            deb = Path(tmp) / "strawwu-initd_0.4.1.12_all.deb"
            deb.write_text("fake", encoding="utf-8")
            os.environ["STRAWWU_TARGET_DEB_DIR"] = tmp
            try:
                found = mod.find_deb_file("strawwu-initd")
                self.assertEqual(deb, found)
            finally:
                os.environ.pop("STRAWWU_TARGET_DEB_DIR", None)

    def test_dry_run_target_setup(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "target-setup.log"
            state = Path(tmp) / "state.json"
            mod.LOG_PATH = log
            os.environ["STRAWWU_SETUP_STATE"] = str(state)
            os.environ["STRAWWU_INITD_LOG"] = str(Path(tmp) / "initd.log")
            try:
                rc = mod.run_target_setup(dry_run=True)
                self.assertEqual(0, rc)
                self.assertTrue(log.exists())
                lines = log.read_text(encoding="utf-8").strip().splitlines()
                self.assertGreaterEqual(len(lines), 2)
            finally:
                os.environ.pop("STRAWWU_SETUP_STATE", None)
                os.environ.pop("STRAWWU_INITD_LOG", None)

    def test_cli_version(self) -> None:
        proc = subprocess.run(
            [str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode)
        self.assertIn("strawwu-target-setup", proc.stdout)


if __name__ == "__main__":
    unittest.main()

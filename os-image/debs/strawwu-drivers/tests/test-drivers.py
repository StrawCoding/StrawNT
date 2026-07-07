#!/usr/bin/env python3
"""Unit tests for strawwu-drivers (fixture mode, no ubuntu-drivers required)."""
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
CONTROL = ROOT / "DEBIAN/control"
CLI = ROOT / "usr/bin/strawwu-drivers"
CORE = ROOT / "usr/lib/strawwu-drivers/core.py"
FIXTURE = ROOT / "usr/share/strawwu/drivers/fixture-catalog.json"
MANIFEST = ROOT / "usr/share/strawwu/drivers/drivers-manifest.yaml"
POLKIT = ROOT / "usr/share/polkit-1/actions/xyz.wastebase.strawwu.drivers.policy"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


class DriversTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.core = _load_module("strawwu_drivers_core", CORE)

    def setUp(self) -> None:
        os.environ["STRAWWU_DRIVERS_FIXTURE"] = "1"
        os.environ["STRAWWU_DRIVERS_FIXTURE_PATH"] = str(FIXTURE)

    def tearDown(self) -> None:
        for key in ("STRAWWU_DRIVERS_FIXTURE", "STRAWWU_DRIVERS_FIXTURE_PATH"):
            os.environ.pop(key, None)

    def test_control_depends(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-drivers", text)
        self.assertIn("ubuntu-drivers-common", text)
        self.assertIn("polkitd", text)

    def test_manifest_vendors(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("nvidia", text)
        self.assertIn("amd", text)
        self.assertIn("intel", text)
        self.assertIn("post-sec-secureboot-route", text)

    def test_polkit_action(self) -> None:
        text = POLKIT.read_text(encoding="utf-8")
        self.assertIn("xyz.wastebase.strawwu.drivers.install", text)

    def test_fixture_has_three_vendors(self) -> None:
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        vendors = {d["vendor"] for d in data["devices"]}
        self.assertEqual({"nvidia", "amd", "intel"}, vendors)

    def test_driver_status_fixture(self) -> None:
        status = self.core.driver_status()
        self.assertTrue(status["mock"])
        self.assertEqual(3, len(status["devices"]))
        self.assertTrue(status["secure_boot"]["enabled"])
        self.assertIn("MOK", status["secure_boot"]["warning"])

    def test_list_drivers_fixture(self) -> None:
        listing = self.core.list_drivers()
        self.assertTrue(listing["mock"])
        self.assertGreaterEqual(len(listing["drivers"]), 2)
        vendors = {d["vendor"] for d in listing["drivers"]}
        self.assertIn("nvidia", vendors)
        self.assertIn("amd", vendors)

    def test_install_mock(self) -> None:
        result = self.core.install_driver("nvidia-driver-550")
        self.assertTrue(result["success"])
        self.assertTrue(result["mock"])

    def test_cli_version(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode)
        self.assertTrue(proc.stdout.strip())

    def test_cli_status_json(self) -> None:
        env = os.environ.copy()
        env["STRAWWU_DRIVERS_FIXTURE"] = "1"
        env["STRAWWU_DRIVERS_FIXTURE_PATH"] = str(FIXTURE)
        proc = subprocess.run(
            [sys.executable, str(CLI), "--json", "status"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        self.assertEqual(0, proc.returncode)
        data = json.loads(proc.stdout)
        self.assertTrue(data["mock"])
        self.assertEqual(3, len(data["devices"]))


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Unit tests for strawwu-laptop (fixture mode, no laptop hardware required)."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "DEBIAN/control"
CLI = ROOT / "usr/bin/strawwu-laptop-peripherals"
CORE = ROOT / "usr/lib/strawwu-laptop/core.py"
FIXTURE = ROOT / "usr/share/strawwu/laptop/fixture-catalog.json"
MANIFEST = ROOT / "usr/share/strawwu/laptop/laptop-peripherals-manifest.yaml"
PROFILE = ROOT / "usr/share/strawwu/laptop/device_profiles/generic-intel-laptop.json"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


class LaptopTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.core = _load_module("strawwu_laptop_core", CORE)

    def setUp(self) -> None:
        os.environ["STRAWWU_LAPTOP_FIXTURE"] = "1"
        os.environ["STRAWWU_LAPTOP_FIXTURE_PATH"] = str(FIXTURE)
        os.environ["STRAWWU_LAPTOP_PROFILES_DIR"] = str(PROFILE.parent)

    def tearDown(self) -> None:
        for key in (
            "STRAWWU_LAPTOP_FIXTURE",
            "STRAWWU_LAPTOP_FIXTURE_PATH",
            "STRAWWU_LAPTOP_PROFILES_DIR",
        ):
            os.environ.pop(key, None)

    def test_control_meta_packages(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-laptop", text)
        self.assertIn("Section: metapackages", text)
        for pkg in ("tlp", "fprintd", "libinput-tools", "v4l-utils", "brightnessctl"):
            self.assertIn(pkg, text)

    def test_manifest_dimensions(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        for dim in ("touchpad", "webcam", "fingerprint", "tlp"):
            self.assertIn(dim, text)

    def test_device_profile_schema(self) -> None:
        data = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual("strawwu-device-profile/v1", data["schema"])
        self.assertIn("touchpad", data["peripherals"])
        self.assertIn("fingerprint", data["peripherals"])
        self.assertTrue(data["community_pr"]["enabled"])

    def test_fixture_all_dimensions(self) -> None:
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        for key in ("touchpad", "fn_keys", "tlp", "webcam", "fingerprint"):
            self.assertIn(key, data)
        self.assertEqual("PASS", data["peripherals"])

    def test_peripheral_status_fixture(self) -> None:
        status = self.core.peripheral_status()
        self.assertTrue(status["mock"])
        self.assertEqual("PASS", status["peripherals"])

    def test_run_smoke_fixture(self) -> None:
        smoke = self.core.run_smoke()
        self.assertEqual("PASS", smoke["smoke"])
        self.assertEqual("PASS", smoke["tests"]["peripherals"])

    def test_list_profiles(self) -> None:
        listing = self.core.list_profiles()
        self.assertGreaterEqual(listing["count"], 1)
        ids = {p["profile_id"] for p in listing["profiles"]}
        self.assertIn("generic-intel-laptop", ids)

    def test_cli_smoke_json(self) -> None:
        env = os.environ.copy()
        env["STRAWWU_LAPTOP_FIXTURE"] = "1"
        env["STRAWWU_LAPTOP_FIXTURE_PATH"] = str(FIXTURE)
        proc = subprocess.run(
            [sys.executable, str(CLI), "--json", "smoke"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        self.assertEqual(0, proc.returncode)
        data = json.loads(proc.stdout)
        self.assertEqual("PASS", data["smoke"])


if __name__ == "__main__":
    unittest.main()

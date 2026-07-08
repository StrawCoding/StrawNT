#!/usr/bin/env python3
"""Unit tests for strawwu-secureboot (fixture mode)."""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "usr" / "lib" / "strawwu-secureboot" / "core.py"
CLI = ROOT / "usr" / "bin" / "strawwu-secureboot"
CONTROL = ROOT / "DEBIAN" / "control"
MANIFEST = ROOT / "usr" / "share" / "strawwu" / "secureboot" / "secureboot-manifest.yaml"
FIXTURE = ROOT / "usr" / "share" / "strawwu" / "secureboot" / "fixture-catalog.json"


def load_core():
    spec = importlib.util.spec_from_file_location("strawwu_secureboot_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class SecurebootPackageTests(unittest.TestCase):
    def test_deb_scaffold(self) -> None:
        self.assertTrue(CONTROL.is_file())
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-secureboot", text)
        self.assertIn("python3", text)

    def test_manifest(self) -> None:
        self.assertTrue(MANIFEST.is_file())
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-secureboot/v1", text)
        self.assertIn("shim.efi", text)
        self.assertIn("vmlinuz", text)

    def test_fixture_schema(self) -> None:
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "strawwu-secureboot-fixture/v1")
        self.assertIn("route", data)
        self.assertIn("boot_chain", data["route"])


class SecurebootCoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.fixture = Path(self.tmp.name) / "fixture.json"
        shutil.copy(FIXTURE, self.fixture)
        os.environ["STRAWWU_SECUREBOOT_FIXTURE"] = "1"
        os.environ["STRAWWU_SECUREBOOT_FIXTURE_PATH"] = str(self.fixture)
        os.environ.pop("STRAWWU_SECURE_BOOT_ENFORCE", None)
        self.mod = load_core()

    def tearDown(self) -> None:
        os.environ.pop("STRAWWU_SECUREBOOT_FIXTURE", None)
        os.environ.pop("STRAWWU_SECUREBOOT_FIXTURE_PATH", None)

    def test_status_fixture(self) -> None:
        status = self.mod.detect_sb_state()
        self.assertTrue(status["enabled"])
        self.assertEqual(status["plan"], "post-sec-secureboot-route")

    def test_route_fixture(self) -> None:
        route = self.mod.route_info()
        self.assertIn("shim.efi", route["boot_chain"])
        self.assertFalse(route["signed_kernel"])

    def test_preflight_fixture(self) -> None:
        pf = self.mod.run_preflight()
        self.assertTrue(pf["ok"])
        self.assertTrue(pf["fixture"])


class SecurebootCliTests(unittest.TestCase):
    def test_cli_route_json(self) -> None:
        env = os.environ.copy()
        env["STRAWWU_SECUREBOOT_FIXTURE"] = "1"
        env["STRAWWU_SECUREBOOT_FIXTURE_PATH"] = str(FIXTURE)
        proc = subprocess.run(
            [sys.executable, str(CLI), "route", "--json"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)
        self.assertEqual(data["schema"], "strawwu-secureboot-route/v1")


if __name__ == "__main__":
    unittest.main()

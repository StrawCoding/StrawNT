#!/usr/bin/env python3
"""Unit tests for strawwu-software-sources (fixture mode)."""
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
CLI = ROOT / "usr/bin/strawwu-software-sources"
CORE = ROOT / "usr/lib/strawwu-software-sources/core.py"
FIXTURE = ROOT / "usr/share/strawwu/software-sources/fixture-catalog.json"
MANIFEST = ROOT / "usr/share/strawwu/software-sources/software-sources-manifest.yaml"
POLKIT = ROOT / "usr/share/polkit-1/actions/xyz.wastebase.strawwu.software-sources.policy"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


class SoftwareSourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.core = _load_module("strawwu_software_sources_core", CORE)

    def setUp(self) -> None:
        os.environ["STRAWWU_SOFTWARE_SOURCES_FIXTURE"] = "1"
        os.environ["STRAWWU_SOFTWARE_SOURCES_FIXTURE_PATH"] = str(FIXTURE)

    def tearDown(self) -> None:
        for key in ("STRAWWU_SOFTWARE_SOURCES_FIXTURE", "STRAWWU_SOFTWARE_SOURCES_FIXTURE_PATH"):
            os.environ.pop(key, None)

    def test_control_depends(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-software-sources", text)
        self.assertIn("strawwu-update-notifier", text)
        self.assertIn("polkitd", text)

    def test_manifest_sources(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("strawwu-official", text)
        self.assertIn("flathub", text)
        self.assertIn("ubuntu-security", text)
        self.assertIn("strawwu-update-notifier", text)

    def test_polkit_action(self) -> None:
        text = POLKIT.read_text(encoding="utf-8")
        self.assertIn("xyz.wastebase.strawwu.software-sources.toggle", text)

    def test_fixture_has_required_sources(self) -> None:
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        ids = {s["id"] for s in data["sources"]}
        self.assertEqual({"strawwu-official", "flathub", "ubuntu-security", "third-party-demo"}, ids)

    def test_list_sources_fixture(self) -> None:
        listing = self.core.list_sources()
        self.assertTrue(listing["mock"])
        self.assertEqual(4, len(listing["sources"]))
        readonly = [s for s in listing["sources"] if s["readonly"]]
        self.assertEqual(2, len(readonly))

    def test_toggle_third_party_fixture(self) -> None:
        result = self.core.toggle_source("third-party-demo", True)
        self.assertTrue(result["success"])
        self.assertTrue(result["mock"])

    def test_toggle_readonly_rejected(self) -> None:
        result = self.core.toggle_source("flathub", False)
        self.assertFalse(result["success"])

    def test_check_updates_fixture(self) -> None:
        result = self.core.check_updates()
        self.assertTrue(result["success"])
        self.assertTrue(result["mock"])
        self.assertEqual(3, result["upgradable"])

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
        env["STRAWWU_SOFTWARE_SOURCES_FIXTURE"] = "1"
        env["STRAWWU_SOFTWARE_SOURCES_FIXTURE_PATH"] = str(FIXTURE)
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
        self.assertEqual(4, len(data["sources"]))


if __name__ == "__main__":
    unittest.main()

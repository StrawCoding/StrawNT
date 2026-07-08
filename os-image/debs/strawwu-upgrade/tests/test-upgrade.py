#!/usr/bin/env python3
"""Unit tests for strawwu-upgrade (fixture mode, no apt required)."""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "usr" / "lib" / "strawwu-upgrade" / "core.py"
CLI = ROOT / "usr" / "bin" / "strawwu-upgrade"
CONTROL = ROOT / "DEBIAN" / "control"
MANIFEST = ROOT / "usr" / "share" / "strawwu" / "upgrade" / "upgrade-manifest.yaml"
FIXTURE = ROOT / "usr" / "share" / "strawwu" / "upgrade" / "fixture-catalog.json"


def load_core():
    spec = importlib.util.spec_from_file_location("strawwu_upgrade_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class UpgradePackageTests(unittest.TestCase):
    def test_deb_scaffold(self) -> None:
        self.assertTrue(CONTROL.is_file())
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-upgrade", text)
        self.assertIn("strawwu-initd", text)

    def test_manifest(self) -> None:
        self.assertTrue(MANIFEST.is_file())
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-upgrade/v1", text)
        self.assertIn("pre-upgrade", text)

    def test_fixture_schema(self) -> None:
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "strawwu-upgrade-fixture/v1")
        self.assertIn("state", data)


class UpgradeCoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.backup = Path(self.tmp.name) / "backups"
        self.state = Path(self.tmp.name) / "state.json"
        self.boot = Path(self.tmp.name) / "boot"
        self.boot.mkdir()
        self.fixture = Path(self.tmp.name) / "fixture.json"
        shutil.copy(FIXTURE, self.fixture)

        state = json.loads(FIXTURE.read_text(encoding="utf-8"))["state"]
        self.state.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

        (self.boot / "vmlinuz-6.8.0-strawwu").write_text("kernel\n", encoding="utf-8")
        (self.boot / "initrd.img-6.8.0-strawwu").write_text("initrd\n", encoding="utf-8")

        os.environ["STRAWWU_UPGRADE_FIXTURE"] = "1"
        os.environ["STRAWWU_UPGRADE_FIXTURE_PATH"] = str(self.fixture)
        os.environ["STRAWWU_UPGRADE_BACKUP_ROOT"] = str(self.backup)
        os.environ["STRAWWU_SETUP_STATE"] = str(self.state)
        os.environ["STRAWWU_UPGRADE_BOOT_DIR"] = str(self.boot)
        os.environ["STRAWWU_VERSION"] = "0.6.3.11"

        self.core = load_core()

    def tearDown(self) -> None:
        for key in (
            "STRAWWU_UPGRADE_FIXTURE",
            "STRAWWU_UPGRADE_FIXTURE_PATH",
            "STRAWWU_UPGRADE_BACKUP_ROOT",
            "STRAWWU_SETUP_STATE",
            "STRAWWU_UPGRADE_BOOT_DIR",
            "STRAWWU_VERSION",
        ):
            os.environ.pop(key, None)

    def test_preflight_ok(self) -> None:
        result = self.core.run_preflight(target_version="0.7.0.0")
        self.assertTrue(result["ok"])
        self.assertEqual(result["target_version"], "0.7.0.0")

    def test_snapshot_and_rollback(self) -> None:
        snap = self.core.create_snapshot("0.7.0.0")
        self.assertTrue((Path(snap["path"]) / "manifest.json").is_file())
        self.assertTrue((Path(snap["path"]) / "state.json").is_file())

        # Mutate live state then rollback.
        mutated = json.loads(self.state.read_text(encoding="utf-8"))
        mutated["lifecycle"]["firstboot"] = "failed"
        self.state.write_text(json.dumps(mutated) + "\n", encoding="utf-8")

        result = self.core.rollback(snap["snapshot"])
        self.assertEqual(result["snapshot"], snap["snapshot"])
        restored = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(restored["lifecycle"]["firstboot"], "done")

    def test_upgrade_dry_run(self) -> None:
        result = self.core.run_upgrade(target_version="0.7.0.0", dry_run=True)
        self.assertTrue(result["dry_run"])
        self.assertTrue(result["snapshot"]["snapshot"].startswith("pre-upgrade-"))

    def test_list_snapshots(self) -> None:
        self.core.create_snapshot("0.7.0.0")
        snaps = self.core.list_snapshots()
        self.assertEqual(len(snaps), 1)
        self.assertTrue(snaps[0]["name"].startswith("pre-upgrade-"))


class UpgradeCliTests(unittest.TestCase):
    def test_cli_version(self) -> None:
        proc = __import__("subprocess").run(
            [sys.executable, str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("strawwu-upgrade", proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

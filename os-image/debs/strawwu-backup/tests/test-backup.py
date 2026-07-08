#!/usr/bin/env python3
"""Unit tests for strawwu-backup (fixture mode, no root required)."""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "usr" / "lib" / "strawwu-backup" / "core.py"
CLI = ROOT / "usr" / "bin" / "strawwu-backup"
CONTROL = ROOT / "DEBIAN" / "control"
MANIFEST = ROOT / "usr" / "share" / "strawwu" / "backup" / "backup-manifest.yaml"
FIXTURE = ROOT / "usr" / "share" / "strawwu" / "backup" / "fixture-catalog.json"


def load_core():
    spec = importlib.util.spec_from_file_location("strawwu_backup_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class BackupPackageTests(unittest.TestCase):
    def test_deb_scaffold(self) -> None:
        self.assertTrue(CONTROL.is_file())
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-backup", text)
        self.assertIn("strawwu-initd", text)
        self.assertIn("strawwu-upgrade", text)

    def test_manifest(self) -> None:
        self.assertTrue(MANIFEST.is_file())
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-backup/v1", text)
        self.assertIn("upgrade_hook", text)
        self.assertIn("timeshift", text)

    def test_fixture_schema(self) -> None:
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "strawwu-backup-fixture/v1")
        self.assertGreaterEqual(len(data["snapshots"]), 2)


class BackupCoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.backup = Path(self.tmp.name) / "backups"
        self.fixture = Path(self.tmp.name) / "fixture.json"
        shutil.copy(FIXTURE, self.fixture)

        os.environ["STRAWWU_BACKUP_FIXTURE"] = "1"
        os.environ["STRAWWU_BACKUP_FIXTURE_PATH"] = str(self.fixture)
        os.environ["STRAWWU_BACKUP_ROOT"] = str(self.backup)
        self.core = load_core()

    def tearDown(self) -> None:
        for key in (
            "STRAWWU_BACKUP_FIXTURE",
            "STRAWWU_BACKUP_FIXTURE_PATH",
            "STRAWWU_BACKUP_ROOT",
        ):
            os.environ.pop(key, None)

    def test_preflight_ok(self) -> None:
        result = self.core.run_preflight()
        self.assertTrue(result["ok"])
        self.assertTrue(result["backends"]["rsync"])

    def test_status_and_list(self) -> None:
        status = self.core.backup_status()
        self.assertEqual(status["schema"], "strawwu-backup-status/v1")
        self.assertGreaterEqual(status["snapshot_count"], 2)
        snaps = self.core.list_snapshots()
        kinds = {s.get("kind") for s in snaps}
        self.assertIn("system", kinds)
        self.assertIn("upgrade", kinds)

    def test_create_and_restore_dry_run(self) -> None:
        created = self.core.create_snapshot(label="unit-test", backend="rsync")
        self.assertIn("snapshot", created)
        self.assertEqual(created["backend"], "rsync")
        plan = self.core.restore_snapshot(created["snapshot"], dry_run=True)
        self.assertTrue(plan["dry_run"])
        self.assertTrue(plan["actions"])

    def test_upgrade_restore_plan(self) -> None:
        plan = self.core.restore_snapshot("pre-upgrade-0.7.0.9", dry_run=True)
        self.assertEqual(plan["kind"], "upgrade")
        self.assertTrue(any("strawwu-upgrade" in a for a in plan["actions"]))


if __name__ == "__main__":
    unittest.main()

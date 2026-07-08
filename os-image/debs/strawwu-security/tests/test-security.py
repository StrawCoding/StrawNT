#!/usr/bin/env python3
"""Unit tests for strawwu-security (fixture mode)."""
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
CORE = ROOT / "usr" / "lib" / "strawwu-security" / "core.py"
CLI = ROOT / "usr" / "bin" / "strawwu-security"
CONTROL = ROOT / "DEBIAN" / "control"
MANIFEST = ROOT / "usr" / "share" / "strawwu" / "security" / "security-manifest.yaml"
FIXTURE = ROOT / "usr" / "share" / "strawwu" / "security" / "fixture-catalog.json"
USN_FIXTURE = ROOT / "usr" / "share" / "strawwu" / "security" / "fixture-usn.json"


def load_core():
    spec = importlib.util.spec_from_file_location("strawwu_security_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class SecurityPackageTests(unittest.TestCase):
    def test_deb_scaffold(self) -> None:
        self.assertTrue(CONTROL.is_file())
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-security", text)
        self.assertIn("python3", text)

    def test_manifest(self) -> None:
        self.assertTrue(MANIFEST.is_file())
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-security/v1", text)
        self.assertIn("post-sec-cve-policy", text)
        self.assertIn("noble", text)

    def test_fixture_schema(self) -> None:
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "strawwu-security-fixture/v1")
        self.assertIn("track", data)
        self.assertIn("summary", data["track"])

    def test_usn_fixture(self) -> None:
        data = json.loads(USN_FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "strawwu-usn-track/v1")
        self.assertTrue(data["notices"])


class SecurityCoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.fixture = Path(self.tmp.name) / "fixture.json"
        self.usn = Path(self.tmp.name) / "usn.json"
        self.fixture.write_text(FIXTURE.read_text(encoding="utf-8"), encoding="utf-8")
        self.usn.write_text(USN_FIXTURE.read_text(encoding="utf-8"), encoding="utf-8")
        os.environ["STRAWWU_CVE_FIXTURE"] = "1"
        os.environ["STRAWWU_CVE_FIXTURE_PATH"] = str(self.fixture)
        os.environ["STRAWWU_CVE_USN_FIXTURE_PATH"] = str(self.usn)
        os.environ.pop("STRAWWU_CVE_NOTIFY", None)
        self.mod = load_core()

    def tearDown(self) -> None:
        os.environ.pop("STRAWWU_CVE_FIXTURE", None)
        os.environ.pop("STRAWWU_CVE_FIXTURE_PATH", None)
        os.environ.pop("STRAWWU_CVE_USN_FIXTURE_PATH", None)

    def test_status_fixture(self) -> None:
        status = self.mod.policy_status()
        self.assertEqual(status["ubuntu_series"], "noble")
        self.assertEqual(status["plan"], "post-sec-cve-policy")

    def test_track_fixture(self) -> None:
        track = self.mod.track_info()
        self.assertEqual(track["schema"], "strawwu-usn-track/v1")
        self.assertGreater(track["summary"]["total"], 0)

    def test_notify_fixture(self) -> None:
        notify = self.mod.notify_info()
        self.assertTrue(notify["dry_run"])
        self.assertEqual(notify["channel"], "security-advisory")

    def test_preflight_fixture(self) -> None:
        pf = self.mod.run_preflight()
        self.assertTrue(pf["ok"])
        self.assertTrue(pf["fixture"])


class SecurityCliTests(unittest.TestCase):
    def test_cli_track_json(self) -> None:
        env = os.environ.copy()
        env["STRAWWU_CVE_FIXTURE"] = "1"
        env["STRAWWU_CVE_FIXTURE_PATH"] = str(FIXTURE)
        env["STRAWWU_CVE_USN_FIXTURE_PATH"] = str(USN_FIXTURE)
        proc = subprocess.run(
            [sys.executable, str(CLI), "track", "--json"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)
        self.assertEqual(data["schema"], "strawwu-usn-track/v1")


if __name__ == "__main__":
    unittest.main()

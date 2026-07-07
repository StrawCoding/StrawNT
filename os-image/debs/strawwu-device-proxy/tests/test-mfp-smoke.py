#!/usr/bin/env python3
"""Unit tests for POST-Q3 MFP smoke OS artifacts."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class MfpSmokeOsTests(unittest.TestCase):
    def test_mfp_fixture_catalog(self) -> None:
        fixture = ROOT / "usr/share/strawwu/device-proxy/mfp-fixture-catalog.json"
        data = json.loads(fixture.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "strawwu-mfp-fixture/v1")
        network = [p for p in data["printers"] if p["connection"] == "network"]
        self.assertGreaterEqual(len(network), 1)
        self.assertEqual(data["print"]["status"], "PASS")
        self.assertEqual(data["scan"]["status"], "PASS")

    def test_manifest_mfp_smoke(self) -> None:
        manifest = ROOT / "usr/share/strawwu/device-proxy/device-proxy-manifest.yaml"
        text = manifest.read_text(encoding="utf-8")
        self.assertIn("mfp_smoke:", text)
        self.assertIn("strawwu mfp smoke", text)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Unit tests for strawwu-device-proxy OS package."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DeviceProxyOsTests(unittest.TestCase):
    def test_udev_rules_exist(self) -> None:
        rules = ROOT / "usr/lib/udev/rules.d/99-strawwu-device-proxy.rules"
        text = rules.read_text(encoding="utf-8")
        self.assertIn("strawwu-com-port", text)
        self.assertIn("strawwu-hid", text)
        self.assertIn("hotplug-notify.sh", text)

    def test_manifest(self) -> None:
        manifest = ROOT / "usr/share/strawwu/device-proxy/device-proxy-manifest.yaml"
        text = manifest.read_text(encoding="utf-8")
        self.assertIn("strawwu devices list", text)
        self.assertIn("DDP0-3", text)

    def test_fixture_catalog(self) -> None:
        fixture = ROOT / "usr/share/strawwu/device-proxy/fixture-catalog.json"
        data = json.loads(fixture.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "strawwu-device-proxy-fixture/v1")
        tiers = {d["tier"] for d in data["devices"]}
        self.assertTrue({"Tier1", "Tier2", "Tier3", "Tier4"} & tiers)

    def test_hotplug_script_executable(self) -> None:
        script = ROOT / "usr/lib/strawwu-device-proxy/hotplug-notify.sh"
        self.assertTrue(script.exists())
        self.assertIn("notify-send", script.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()

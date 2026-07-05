#!/usr/bin/env python3
"""Unit tests for strawwu-target-identity."""
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/target-identity/target-identity-manifest.yaml"
GRUB_DROPIN = ROOT / "etc/default/grub.d/99-strawwu-identity.cfg"
CLI = ROOT / "usr/bin/strawwu-target-identity"
CORE = ROOT / "usr/lib/strawwu-target-identity/core.py"


def _load_core():
    spec = importlib.util.spec_from_file_location("strawwu_target_identity_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class TargetIdentityTests(unittest.TestCase):
    def test_control_depends_initd(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-target-identity", text)
        self.assertIn("Depends: strawwu-initd", text)

    def test_manifest_schema(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-target-identity-manifest/v1", text)
        self.assertIn("distributor: StrawWU", text)
        self.assertIn("strawwu-boot", text)
        self.assertIn("SWU-IN-003", text)

    def test_grub_dropin_content(self) -> None:
        text = GRUB_DROPIN.read_text(encoding="utf-8")
        self.assertIn('GRUB_DISTRIBUTOR="StrawWU"', text)
        self.assertNotIn("Ubuntu", text)

    def test_dry_run_target_identity(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "target-identity.log"
            state = Path(tmp) / "state.json"
            grub_dropin = Path(tmp) / "grub.d" / "99-strawwu-identity.cfg"
            grub_main = Path(tmp) / "default" / "grub"
            grub_main.parent.mkdir(parents=True)
            grub_main.write_text('GRUB_DISTRIBUTOR="Ubuntu"\n', encoding="utf-8")

            mod.LOG_PATH = log
            mod.GRUB_DROPIN = grub_dropin
            mod.GRUB_MAIN = grub_main
            mod.PLYMOUTH_THEME = Path("/nonexistent/theme.plymouth")
            mod.MARKER_PATH = Path(tmp) / "marker.ok"

            os.environ["STRAWWU_SETUP_STATE"] = str(state)
            os.environ["STRAWWU_INITD_LOG"] = str(Path(tmp) / "initd.log")
            try:
                rc = mod.run_target_identity(dry_run=True)
                self.assertEqual(0, rc)
                self.assertTrue(log.exists())
            finally:
                os.environ.pop("STRAWWU_SETUP_STATE", None)
                os.environ.pop("STRAWWU_INITD_LOG", None)

    def test_cli_version(self) -> None:
        proc = __import__("subprocess").run(
            [str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode)
        self.assertIn("strawwu-target-identity", proc.stdout)


if __name__ == "__main__":
    unittest.main()

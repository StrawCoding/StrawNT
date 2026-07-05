#!/usr/bin/env python3
"""Unit tests for strawwu-disable-upstream-init."""
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/disable-upstream-init/disable-upstream-init-manifest.yaml"
CLOUD_DISABLED = ROOT / "etc/cloud/cloud-init.disabled"
DCONF = ROOT / "etc/dconf/db/local.d/01-strawwu-no-gnome-initial-setup"
CLI = ROOT / "usr/bin/strawwu-disable-upstream-init"
CORE = ROOT / "usr/lib/strawwu-disable-upstream-init/core.py"


def _load_core():
    spec = importlib.util.spec_from_file_location("strawwu_disable_upstream_init_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class DisableUpstreamInitTests(unittest.TestCase):
    def test_control_depends_initd(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-disable-upstream-init", text)
        self.assertIn("Depends: strawwu-initd", text)

    def test_manifest_schema(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-disable-upstream-init-manifest/v1", text)
        self.assertIn("cloud-init.service", text)
        self.assertIn("gnome-initial-setup.service", text)
        self.assertIn("ubuntu-desktop", text)
        self.assertIn("SWU-IN-004", text)

    def test_cloud_init_disabled_marker_shipped(self) -> None:
        self.assertTrue(CLOUD_DISABLED.is_file())

    def test_dconf_keyfile_content(self) -> None:
        text = DCONF.read_text(encoding="utf-8")
        self.assertIn("[org/gnome/InitialSetup]", text)
        self.assertIn("has-completed-setup=true", text)

    def test_dry_run_disable_upstream_init(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "disable-upstream-init.log"
            state = Path(tmp) / "state.json"
            cloud = Path(tmp) / "cloud" / "cloud-init.disabled"
            dconf = Path(tmp) / "dconf" / "01-strawwu-no-gnome-initial-setup"
            systemd = Path(tmp) / "systemd" / "system"
            marker = Path(tmp) / "marker.ok"

            mod.LOG_PATH = log
            mod.CLOUD_INIT_DISABLED = cloud
            mod.DCONF_KEYFILE = dconf
            mod.MARKER_PATH = marker

            original_mask = mod.mask_systemd_unit

            def _mask(unit: str, *, dry_run: bool = False) -> None:
                if dry_run:
                    return
                link = systemd / unit
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to("/dev/null")

            mod.mask_systemd_unit = _mask  # type: ignore[assignment]

            os.environ["STRAWWU_SETUP_STATE"] = str(state)
            os.environ["STRAWWU_INITD_LOG"] = str(Path(tmp) / "initd.log")
            try:
                rc = mod.run_disable_upstream_init(skip_meta_purge=True, dry_run=True)
                self.assertEqual(0, rc)
                self.assertTrue(log.exists())
            finally:
                os.environ.pop("STRAWWU_SETUP_STATE", None)
                os.environ.pop("STRAWWU_INITD_LOG", None)
                mod.mask_systemd_unit = original_mask  # type: ignore[assignment]

    def test_cli_version(self) -> None:
        proc = __import__("subprocess").run(
            [str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode)
        self.assertIn("strawwu-disable-upstream-init", proc.stdout)


if __name__ == "__main__":
    unittest.main()

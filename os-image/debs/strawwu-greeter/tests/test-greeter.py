#!/usr/bin/env python3
"""Unit tests for strawwu-greeter."""
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/greeter/greeter-manifest.yaml"
DCONF = ROOT / "usr/share/strawwu/greeter/greeter.dconf-defaults"
GDM_DCONF = ROOT / "etc/gdm3/greeter.dconf-defaults"
CSS = ROOT / "usr/share/gnome-shell/theme/strawwu-greeter.css"
LIVE_EXAMPLE = ROOT / "usr/share/strawwu/greeter/live-autologin.conf.example"
CLI = ROOT / "usr/bin/strawwu-greeter"
CORE = ROOT / "usr/lib/strawwu-greeter/core.py"


def _load_core():
    spec = importlib.util.spec_from_file_location("strawwu_greeter_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class GreeterTests(unittest.TestCase):
    def test_control_depends(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-greeter", text)
        self.assertIn("Depends: strawwu-initd", text)
        self.assertIn("strawwu-session", text)
        self.assertIn("gdm3", text)

    def test_manifest_schema(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-greeter-manifest/v1", text)
        self.assertIn("default_session: strawwu-session", text)
        self.assertIn("SWU-GR-001", text)
        self.assertIn("StrawWU-Dark", text)

    def test_greeter_dconf_defaults(self) -> None:
        for path in (DCONF, GDM_DCONF):
            text = path.read_text(encoding="utf-8")
            self.assertIn("gtk-theme='StrawWU-Dark'", text)
            self.assertIn("disable-user-list=true", text)
            self.assertNotIn("Ubuntu", text)

    def test_greeter_css_branding(self) -> None:
        text = CSS.read_text(encoding="utf-8")
        self.assertIn("#2dd4bf", text)
        self.assertIn("distributor-logo.svg", text)
        self.assertNotIn("ubuntu", text.lower())

    def test_live_autologin_example(self) -> None:
        text = LIVE_EXAMPLE.read_text(encoding="utf-8")
        self.assertIn("AutomaticLogin=ubuntu", text.replace(" ", ""))

    def test_dry_run_apply(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "greeter.log"
            state = Path(tmp) / "state.json"
            gdm_dconf = Path(tmp) / "greeter.dconf-defaults"
            shipped = Path(tmp) / "shipped.dconf-defaults"
            custom = Path(tmp) / "custom.conf"
            css = Path(tmp) / "strawwu-greeter.css"
            marker = Path(tmp) / "greeter.ok"

            shipped.write_text(DCONF.read_text(encoding="utf-8"), encoding="utf-8")
            custom.write_text("[daemon]\n", encoding="utf-8")
            css.write_text("/* test */", encoding="utf-8")

            mod.LOG_PATH = log
            mod.GDM_GREETER_DCONF = gdm_dconf
            mod.SHIPPED_DCONF = shipped
            mod.GDM_CUSTOM = custom
            mod.GREETER_CSS = css
            mod.MARKER_PATH = marker

            os.environ["STRAWWU_SETUP_STATE"] = str(state)
            os.environ["STRAWWU_INITD_LOG"] = str(Path(tmp) / "initd.log")
            try:
                rc = mod.run_greeter_apply(dry_run=True)
                self.assertEqual(0, rc)
                self.assertTrue(log.exists())
            finally:
                os.environ.pop("STRAWWU_SETUP_STATE", None)
                os.environ.pop("STRAWWU_INITD_LOG", None)

    def test_apply_writes_dconf_and_session(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "greeter.log"
            state = Path(tmp) / "state.json"
            gdm_dconf = Path(tmp) / "greeter.dconf-defaults"
            shipped = Path(tmp) / "shipped.dconf-defaults"
            custom = Path(tmp) / "custom.conf"
            css = Path(tmp) / "strawwu-greeter.css"
            marker = Path(tmp) / "greeter.ok"

            shipped.write_text(DCONF.read_text(encoding="utf-8"), encoding="utf-8")
            custom.write_text("[daemon]\n", encoding="utf-8")
            css.write_text(CSS.read_text(encoding="utf-8"), encoding="utf-8")

            mod.LOG_PATH = log
            mod.GDM_GREETER_DCONF = gdm_dconf
            mod.SHIPPED_DCONF = shipped
            mod.GDM_CUSTOM = custom
            mod.GREETER_CSS = css
            mod.MARKER_PATH = marker

            def _initd_ok(*args: str, dry_run: bool = False) -> int:
                return 0

            original_initd = mod.initd_cmd
            mod.initd_cmd = _initd_ok  # type: ignore[assignment]

            os.environ["STRAWWU_SETUP_STATE"] = str(state)
            os.environ["STRAWWU_INITD_LOG"] = str(Path(tmp) / "initd.log")
            try:
                rc = mod.run_greeter_apply(dry_run=False)
                self.assertEqual(0, rc)
                self.assertIn("StrawWU-Dark", gdm_dconf.read_text(encoding="utf-8"))
                self.assertIn("DefaultSession=strawwu-session", custom.read_text(encoding="utf-8"))
                self.assertTrue(marker.is_file())
            finally:
                os.environ.pop("STRAWWU_SETUP_STATE", None)
                os.environ.pop("STRAWWU_INITD_LOG", None)
                mod.initd_cmd = original_initd  # type: ignore[assignment]

    def test_cli_version(self) -> None:
        proc = __import__("subprocess").run(
            [str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode)
        self.assertIn("strawwu-greeter", proc.stdout)


if __name__ == "__main__":
    unittest.main()

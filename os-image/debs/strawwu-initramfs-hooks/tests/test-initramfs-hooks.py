#!/usr/bin/env python3
"""Unit tests for strawwu-initramfs-hooks."""
from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/initramfs-hooks/initramfs-hooks-manifest.yaml"
CLI = ROOT / "usr/bin/strawwu-initramfs-hooks"
CORE = ROOT / "usr/lib/strawwu-initramfs-hooks/core.py"
DISK_BOOT = ROOT / "etc/initramfs-tools/conf.d/strawwu-disk-boot"


def _load_core():
    spec = importlib.util.spec_from_file_location("strawwu_initramfs_hooks_core", CORE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class InitramfsHooksTests(unittest.TestCase):
    def test_control_package_name(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn("Package: strawwu-initramfs-hooks", text)
        self.assertIn("Depends: strawwu-initd", text)

    def test_manifest_schema(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-initramfs-hooks-manifest/v1", text)
        self.assertIn("BOOT=local", text)
        self.assertIn("/usr/share/initramfs-tools/hooks/casper", text)
        self.assertIn("lifecycle.initramfs_hooks", text)

    def test_disk_boot_conf(self) -> None:
        text = DISK_BOOT.read_text(encoding="utf-8")
        self.assertIn("BOOT=local", text)
        self.assertIn("strawwu-initramfs-hooks", text)

    def test_strip_live_hooks_dry_run(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            hooks = Path(tmp) / "usr/share/initramfs-tools/hooks"
            scripts = Path(tmp) / "usr/share/initramfs-tools/scripts"
            hooks.mkdir(parents=True)
            scripts.mkdir(parents=True)
            casper_hook = hooks / "casper"
            casper_hook.write_text("# fake", encoding="utf-8")
            casper_script = scripts / "casper"
            casper_script.write_text("# fake", encoding="utf-8")
            live_script = scripts / "live-bottom"
            live_script.mkdir()

            orig_hooks = mod.HOOK_FILES[:]
            orig_globs = mod.SCRIPT_GLOBS[:]
            try:
                mod.HOOK_FILES = [hooks / "casper"]
                mod.SCRIPT_GLOBS = [
                    str(scripts / "casper*"),
                    str(scripts / "live*"),
                ]
                removed = mod.strip_live_initramfs_hooks(dry_run=True)
                self.assertGreaterEqual(removed, 1)
                self.assertTrue(casper_hook.exists())
            finally:
                mod.HOOK_FILES = orig_hooks
                mod.SCRIPT_GLOBS = orig_globs

    def test_strip_live_hooks_removes_files(self) -> None:
        mod = _load_core()
        with tempfile.TemporaryDirectory() as tmp:
            hooks = Path(tmp) / "hooks"
            scripts = Path(tmp) / "scripts"
            hooks.mkdir()
            scripts.mkdir()
            (hooks / "casper").write_text("x", encoding="utf-8")
            (scripts / "casper-bottom").write_text("x", encoding="utf-8")

            orig_hooks = mod.HOOK_FILES[:]
            orig_conf = mod.CONF_FILES[:]
            orig_globs = mod.SCRIPT_GLOBS[:]
            try:
                mod.HOOK_FILES = [hooks / "casper"]
                mod.CONF_FILES = []
                mod.SCRIPT_GLOBS = [str(scripts / "casper*")]
                removed = mod.strip_live_initramfs_hooks(dry_run=False)
                self.assertGreaterEqual(removed, 2)
                self.assertFalse((hooks / "casper").exists())
                self.assertFalse((scripts / "casper-bottom").exists())
            finally:
                mod.HOOK_FILES = orig_hooks
                mod.CONF_FILES = orig_conf
                mod.SCRIPT_GLOBS = orig_globs

    def test_cli_version(self) -> None:
        proc = subprocess.run(
            [str(CLI), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode)
        self.assertIn("strawwu-initramfs-hooks", proc.stdout)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Unit tests for strawwu-registry-hooks."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = ROOT.parents[2]
COMPONENTS = REPO_ROOT / "components"
SCAN_CLI = ROOT / "usr/bin/strawwu-registry-scan"
APT_HOOK = ROOT / "usr/lib/strawwu-registry-hooks/apt-post-invoke"
FLATPAK_TRIGGER = ROOT / "usr/share/flatpak/triggers/strawwu-registry-scan"
APT_CONF = ROOT / "etc/apt/apt.conf.d/99strawwu-registry-hooks"
MANIFEST = ROOT / "usr/share/strawwu/registry-hooks/registry-hooks-manifest.yaml"


class RegistryHooksTests(unittest.TestCase):
    def test_manifest_schema(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn("schema: strawwu-registry-hooks-manifest/v1", text)
        self.assertIn("scan_cli: /usr/bin/strawwu-registry-scan", text)

    def test_apt_conf_post_invoke(self) -> None:
        text = APT_CONF.read_text(encoding="utf-8")
        self.assertIn("DPkg::Post-Invoke", text)
        self.assertIn("apt-post-invoke", text)

    def test_hook_scripts_executable(self) -> None:
        for path in (APT_HOOK, FLATPAK_TRIGGER, SCAN_CLI):
            self.assertTrue(path.is_file(), path)
            self.assertTrue(os.access(path, os.X_OK), path)

    def test_scan_linux_integration(self) -> None:
        cli = COMPONENTS / "target/debug/strawwu-app-registry"
        if not cli.is_file():
            subprocess.run(
                ["cargo", "build", "--package", "strawwu-app-registry"],
                cwd=COMPONENTS,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        self.assertTrue(cli.is_file(), "strawwu-app-registry binary missing")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            registry = tmp_path / "app-registry.json"
            apps_dir = tmp_path / "applications"
            apps_dir.mkdir()
            desktop = apps_dir / "demo-linux-app.desktop"
            desktop.write_text(
                "[Desktop Entry]\n"
                "Type=Application\n"
                "Name=Demo Linux\n"
                "Exec=/usr/bin/demo-linux\n",
                encoding="utf-8",
            )

            env = os.environ.copy()
            env["STRAWWU_APP_REGISTRY"] = str(registry)
            env["STRAWWU_APP_REGISTRY_CLI"] = str(cli)
            env["STRAWWU_LINUX_DESKTOP_DIRS"] = str(apps_dir)

            # scan via registry CLI directly with custom dir through env is not wired;
            # use strawwu-app-registry scan with temp desktop dir via ScanOptions env —
            # preflight integration test covers full path; here verify wrapper forwards.
            proc = subprocess.run(
                [sys.executable, str(SCAN_CLI), "--linux", "--dry-run", "--json"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("discovered", proc.stdout)

    def test_skip_env_honored(self) -> None:
        env = os.environ.copy()
        env["STRAWWU_SKIP_REGISTRY_SCAN"] = "1"
        for script in (APT_HOOK, FLATPAK_TRIGGER):
            proc = subprocess.run([str(script)], env=env, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, script)


if __name__ == "__main__":
    unittest.main()

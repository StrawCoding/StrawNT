#!/usr/bin/env python3
"""Unit tests for POST-I2 LUKS + dual-boot Calamares settings."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARTITION = ROOT / "etc/calamares/modules/partition.conf"
FSTAB = ROOT / "etc/calamares/modules/fstab.conf"
GRUBCFG = ROOT / "etc/calamares/modules/grubcfg.conf"
WELCOME = ROOT / "etc/calamares/modules/welcome.conf"
SETTINGS = ROOT / "etc/calamares/settings.conf"
DUALBOOT_SH = ROOT / "usr/local/lib/calamares/strawwu-dualboot-detect.sh"
DUALBOOT_CONF = ROOT / "etc/calamares/modules/shellprocess_dualboot-detect.conf"
TS = ROOT / "usr/share/calamares/lang/calamares_zh_TW.ts"
SCEN_LUKS = ROOT.parent.parent.parent / "tests/install-e2e/scenarios/luks-scenario.marker.json"
SCEN_DUAL = ROOT.parent.parent.parent / "tests/install-e2e/scenarios/dualboot-scenario.marker.json"


def test_partition_luks_enabled() -> None:
    text = PARTITION.read_text(encoding="utf-8")
    assert "luksGeneration: luks1" in text
    assert "enableLuksAutomatedPartitioning: true" in text


def test_grub_cryptodisk_and_os_prober() -> None:
    text = GRUBCFG.read_text(encoding="utf-8")
    assert "GRUB_ENABLE_CRYPTODISK: true" in text
    assert "GRUB_DISABLE_OS_PROBER: false" in text


def test_fstab_crypttab_luks() -> None:
    text = FSTAB.read_text(encoding="utf-8")
    assert "crypttabOptions: luks" in text


def test_welcome_storage_requirement() -> None:
    text = WELCOME.read_text(encoding="utf-8")
    assert "requiredStorage:" in text
    assert "storage" in text


def test_dualboot_detect_wired() -> None:
    assert DUALBOOT_SH.is_file()
    assert DUALBOOT_CONF.is_file()
    settings = SETTINGS.read_text(encoding="utf-8")
    assert "dualboot_detect" in settings
    assert "shellprocess@dualboot_detect" in settings


def test_zh_tw_partition_dualboot_luks() -> None:
    text = TS.read_text(encoding="utf-8")
    assert "PartitionPage" in text
    assert "與現有系統並存安裝" in text
    assert "加密系統磁碟（LUKS）" in text


def test_scenario_markers() -> None:
    for path in (SCEN_LUKS, SCEN_DUAL):
        data = json.loads(path.read_text(encoding="utf-8"))
        assert data["schema"] == "strawwu-install-e2e-scenario/v1"
        assert data["stage"] == "post-i2-calamares-luks"
        assert "marker" in data


def test_dualboot_script_syntax() -> None:
    proc = subprocess.run(["bash", "-n", str(DUALBOOT_SH)], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr or proc.stdout


def main() -> int:
    tests = [
        test_partition_luks_enabled,
        test_grub_cryptodisk_and_os_prober,
        test_fstab_crypttab_luks,
        test_welcome_storage_requirement,
        test_dualboot_detect_wired,
        test_zh_tw_partition_dualboot_luks,
        test_scenario_markers,
        test_dualboot_script_syntax,
    ]
    failed = 0
    for fn in tests:
        try:
            fn()
            print(f"PASS: {fn.__name__}")
        except AssertionError as exc:
            print(f"FAIL: {fn.__name__}: {exc}", file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

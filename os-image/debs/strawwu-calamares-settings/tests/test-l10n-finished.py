#!/usr/bin/env python3
"""Unit tests for Calamares zh_TW finished-page l10n overlay (W5-N4)."""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TS = ROOT / "usr/share/calamares/lang/calamares_zh_TW.ts"
FINISHED_COPY = (
    ROOT.parent
    / "strawwu-live-install-ux/usr/share/strawwu/installer/finished-copy.yaml"
)
BUILD = ROOT / "build-deb.sh"


def test_ts_exists() -> None:
    assert TS.is_file(), TS


def test_ts_finished_strings() -> None:
    text = TS.read_text(encoding="utf-8")
    assert "全部完成" in text
    assert "完成後立即重新開機" in text
    assert "安裝未完成" in text
    assert "Ubuntu" not in text


def test_ts_aligns_with_finished_copy() -> None:
    copy = FINISHED_COPY.read_text(encoding="utf-8")
    ts = TS.read_text(encoding="utf-8")
    assert "全部完成" in copy
    assert "全部完成" in ts
    assert "重新開機" in copy
    assert "重新開機" in ts


def test_lrelease_builds_qm() -> None:
    # Build in a temp dir — never mutate tracked source-tree .qm (preflight race).
    with tempfile.TemporaryDirectory() as tmp:
        qm = Path(tmp) / "calamares_zh_TW.qm"
        proc = subprocess.run(
            ["lrelease", str(TS), "-qm", str(qm)],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            raise AssertionError(f"lrelease failed: {proc.stderr or proc.stdout}")
        assert qm.is_file() and qm.stat().st_size > 0


def test_build_script_compiles_lang() -> None:
    text = BUILD.read_text(encoding="utf-8")
    assert "calamares_zh_TW.ts" in text
    assert "lrelease" in text


def main() -> int:
    tests = [
        test_ts_exists,
        test_ts_finished_strings,
        test_ts_aligns_with_finished_copy,
        test_lrelease_builds_qm,
        test_build_script_compiles_lang,
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

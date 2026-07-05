#!/usr/bin/env python3
"""Unit tests for strawwu-wincompat OS baseline (W3-W0)."""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
BASELINE = ROOT / "usr/share/strawwu/wincompat/baseline.yaml"
BUILD = ROOT / "build-deb.sh"
REPO_ROOT = ROOT.parents[2]


def test_control_metadata() -> None:
    text = CONTROL.read_text(encoding="utf-8")
    assert "Package: strawwu-wincompat" in text
    assert "Architecture: amd64" in text
    assert "libc6" in text


def test_build_deb_contains_strawwu() -> None:
    env = os.environ.copy()
    env["STRAWWU_VERSION"] = "0.0.0-test"
    with tempfile.TemporaryDirectory() as tmp:
        env["TMPDIR"] = tmp
        proc = subprocess.run(
            ["bash", str(BUILD)],
            cwd=str(ROOT),
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=600,
        )
        assert proc.returncode == 0, proc.stderr or proc.stdout
        deb = ROOT / "output/strawwu-wincompat_0.0.0-test_amd64.deb"
        assert deb.is_file(), proc.stdout
        listing = subprocess.run(
            ["dpkg-deb", "-c", str(deb)],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        assert "./usr/bin/strawwu" in listing
        assert "./usr/share/strawwu/wincompat/baseline.yaml" in listing


def test_strawwu_status_from_components() -> None:
    binary = REPO_ROOT / "components/target/release/strawwu"
    if not binary.is_file():
        subprocess.run(
            ["cargo", "build", "--release", "-p", "strawwu-launcher"],
            cwd=str(REPO_ROOT / "components"),
            check=True,
            timeout=600,
        )
    assert binary.is_file()
    proc = subprocess.run(
        [str(binary), "status"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0
    assert "status" in proc.stdout.lower()


def test_strawwu_version_from_components() -> None:
    binary = REPO_ROOT / "components/target/release/strawwu"
    assert binary.is_file()
    proc = subprocess.run(
        [str(binary), "version"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0
    assert proc.stdout.strip().startswith("strawwu ")


def main() -> int:
    tests = [
        test_control_metadata,
        test_build_deb_contains_strawwu,
        test_strawwu_status_from_components,
        test_strawwu_version_from_components,
    ]
    failed = 0
    for test in tests:
        name = test.__name__
        try:
            test()
            print(f"PASS: {name}")
        except AssertionError as exc:
            failed += 1
            print(f"FAIL: {name}: {exc}")
    print(f"=== {len(tests) - failed}/{len(tests)} passed ===")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

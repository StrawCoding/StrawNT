#!/usr/bin/env python3
"""Unit tests for strawwu-minimal meta control + meta-audit manifest."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/meta-audit/meta-audit-manifest.yaml"

FORBIDDEN = (
    "ubuntu-pro-client",
    "ubuntu-advantage",
    "ubuntu-report",
    "snapd",
    "apport",
    "whoopsie",
)

REQUIRED_DEPENDS = (
    "apt",
    "ubuntu-keyring",
    "sudo",
    "python3",
    "netplan.io",
)


def _dep_fields(text: str) -> str:
    fields: list[str] = []
    in_dep = False
    for line in text.splitlines():
        if line.startswith(("Depends:", "Recommends:", "Pre-Depends:")):
            fields.append(line)
            in_dep = True
        elif in_dep and line.startswith(" "):
            fields.append(line)
        else:
            in_dep = False
    return "\n".join(fields).lower()


def test_forbidden_absent() -> None:
    deps = _dep_fields(CONTROL.read_text())
    for pkg in FORBIDDEN:
        assert re.search(rf"\b{re.escape(pkg)}\b", deps) is None, pkg


def test_required_depends_present() -> None:
    deps = _dep_fields(CONTROL.read_text())
    for pkg in REQUIRED_DEPENDS:
        assert pkg in deps, pkg


def test_conflicts_ubuntu_minimal() -> None:
    text = CONTROL.read_text().lower()
    assert "conflicts: ubuntu-minimal" in text.replace("\n ", " ")
    assert "breaks:" in text and "ubuntu-minimal" in text


def test_meta_section() -> None:
    text = CONTROL.read_text()
    assert "Section: metapackages" in text
    assert "Package: strawwu-minimal" in text


def test_manifest_schema() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    assert "schema: strawwu-meta-audit-manifest/v1" in text
    assert "wave: W6-B5" in text
    for pkg in ("ubuntu-minimal", "ubuntu-desktop", "ubuntu-keyring"):
        assert pkg in text, pkg
    assert "strawwu-minimal" in text
    assert "strawwu-desktop" in text


def main() -> int:
    tests = [
        test_forbidden_absent,
        test_required_depends_present,
        test_conflicts_ubuntu_minimal,
        test_meta_section,
        test_manifest_schema,
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

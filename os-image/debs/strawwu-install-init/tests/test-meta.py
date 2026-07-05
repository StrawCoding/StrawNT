#!/usr/bin/env python3
"""Unit tests for strawwu-install-init meta control + manifest."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
MANIFEST = ROOT / "usr/share/strawwu/install-init/install-init-manifest.yaml"

REQUIRED_DEPENDS = (
    "strawwu-initd",
    "strawwu-target-setup",
    "strawwu-firstboot",
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


def test_required_depends_present() -> None:
    deps = _dep_fields(CONTROL.read_text())
    for pkg in REQUIRED_DEPENDS:
        assert pkg in deps, pkg


def test_meta_section() -> None:
    text = CONTROL.read_text()
    assert "Section: metapackages" in text
    assert "Package: strawwu-install-init" in text


def test_manifest_schema() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    assert "schema: strawwu-install-init-manifest/v1" in text
    assert "wave: W5-N4" in text
    for pkg in REQUIRED_DEPENDS:
        assert pkg in text, pkg


def test_manifest_l10n_paths() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    assert "calamares_zh_TW.qm" in text or "calamares_qm" in text
    assert "firstboot" in text and "zh_TW" in text


def main() -> int:
    tests = [
        test_required_depends_present,
        test_meta_section,
        test_manifest_schema,
        test_manifest_l10n_paths,
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

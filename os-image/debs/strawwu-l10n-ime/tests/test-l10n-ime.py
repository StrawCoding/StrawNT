#!/usr/bin/env python3
"""Unit tests for strawwu-l10n-ime package."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTROL = ROOT / "debian/control"
IME_MANIFEST = ROOT / "usr/share/strawwu/l10n-ime/ime-manifest.yaml"
LOCALE_POLICY = ROOT / "usr/share/strawwu/l10n-ime/locale-policy.yaml"
FCITX_PROFILE = ROOT / "usr/share/fcitx5/default/conf/profile"
ENV_IME = ROOT / "etc/environment.d/95-strawwu-ime.conf"

REQUIRED_DEPENDS = (
    "fcitx5",
    "fcitx5-chewing",
    "fcitx5-table-cangjie5",
    "fonts-noto-cjk",
    "im-config",
)

FORBIDDEN = ("ibus",)


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


def test_required_depends() -> None:
    deps = _dep_fields(CONTROL.read_text())
    for pkg in REQUIRED_DEPENDS:
        assert pkg in deps, pkg


def test_no_ibus() -> None:
    deps = _dep_fields(CONTROL.read_text())
    for pkg in FORBIDDEN:
        assert re.search(rf"\b{re.escape(pkg)}\b", deps) is None, pkg


def test_ime_manifest() -> None:
    text = IME_MANIFEST.read_text()
    assert "schema: strawwu-ime-manifest/v1" in text
    assert "framework: fcitx5" in text
    assert "chewing" in text
    assert "cangjie5" in text
    assert "GTK_IM_MODULE: fcitx" in text


def test_locale_policy() -> None:
    text = LOCALE_POLICY.read_text()
    assert "schema: strawwu-l10n-policy/v1" in text
    assert "default_locale: zh_TW.UTF-8" in text
    assert "en_US.UTF-8" in text


def test_fcitx_profile() -> None:
    text = FCITX_PROFILE.read_text()
    assert "DefaultIM=chewing" in text
    assert "Name=chewing" in text
    assert "Name=cangjie5" in text


def test_environment_ime() -> None:
    text = ENV_IME.read_text()
    assert "GTK_IM_MODULE=fcitx" in text
    assert "QT_IM_MODULE=fcitx" in text
    assert "XMODIFIERS=@im=fcitx" in text


def main() -> int:
    tests = [
        test_required_depends,
        test_no_ibus,
        test_ime_manifest,
        test_locale_policy,
        test_fcitx_profile,
        test_environment_ime,
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

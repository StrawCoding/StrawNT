#!/usr/bin/env python3
"""Unit tests for strawwu-bug-reporter privacy filter."""

from __future__ import annotations

import sys
import tempfile
import zipfile
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent / "usr/lib/strawwu-bug-reporter"
sys.path.insert(0, str(LIB))

from filter import redact_line, redact_text  # noqa: E402
from bundle import (  # noqa: E402
    BUNDLE_FORMAT,
    build_manifest,
    create_bundle,
    validate_bundle,
)


def assert_contains(haystack: str, needle: str, label: str) -> None:
    if needle not in haystack:
        raise AssertionError(f"{label}: expected {needle!r} in output")


def assert_not_contains(haystack: str, needle: str, label: str) -> None:
    if needle in haystack:
        raise AssertionError(f"{label}: sensitive {needle!r} leaked")


def test_redact_password() -> None:
    out = redact_line("user password=SuperSecret123 logged in")
    assert_not_contains(out, "SuperSecret123", "password")
    assert_contains(out, "[REDACTED]", "password marker")


def test_redact_token_and_key() -> None:
    out = redact_text("token=abc123\n-----BEGIN OPENSSH PRIVATE KEY-----\n/home/alice/secret.txt")
    assert_not_contains(out, "abc123", "token")
    assert_not_contains(out, "-----BEGIN", "ssh key")
    assert_not_contains(out, "/home/alice/", "home path")


def test_manifest_defaults() -> None:
    m = build_manifest()
    assert m["format"] == BUNDLE_FORMAT
    assert m["consent"]["auto_upload_default"] is False
    assert m["consent"]["upload_requested"] is False
    assert m["privacy"]["home_contents_included"] is False


def test_bundle_create_and_validate() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "test.strawwu-bug"
        create_bundle(out, notes="unit test", dry_run=False)
        errors = validate_bundle(out)
        if errors:
            raise AssertionError(f"bundle invalid: {errors}")
        with zipfile.ZipFile(out) as zf:
            manifest = zf.read("manifest.json").decode()
            assert BUNDLE_FORMAT in manifest
            journal = zf.read("journal.txt").decode()
            assert "password=" not in journal.lower() or "[REDACTED]" in journal


def main() -> int:
    tests = [
        test_redact_password,
        test_redact_token_and_key,
        test_manifest_defaults,
        test_bundle_create_and_validate,
    ]
    for fn in tests:
        fn()
        print(f"PASS: {fn.__name__}")
    print(f"=== {len(tests)} privacy/bundle tests OK ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

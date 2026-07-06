#!/usr/bin/env python3
"""Validate StrawWU release-manifest.json schema (W7-RE1)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()
FAILURES: list[str] = []

ALLOWED_CHANNELS = {"dev", "nightly", "beta", "stable"}
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"FAIL: {msg}", file=sys.stderr)


def ok(msg: str) -> None:
    print(f"PASS: {msg}")


def validate_manifest(path: Path, expect_version: str | None = None) -> None:
    if not path.is_file():
        fail(f"manifest missing {path}")
        return

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON {path}: {exc}")
        return

    ok(f"valid JSON {path}")

    schema = data.get("schema")
    if schema == "strawwu-release-manifest/v1":
        ok("schema strawwu-release-manifest/v1")
    else:
        fail(f"unexpected schema: {schema!r}")

    version = data.get("version")
    if isinstance(version, str) and VERSION_RE.match(version):
        ok(f"version field {version}")
    else:
        fail(f"invalid version field: {version!r}")

    if expect_version and version != expect_version:
        fail(f"version mismatch: manifest={version} expected={expect_version}")
    else:
        ok("version matches expectation")

    channel = data.get("channel")
    if channel in ALLOWED_CHANNELS:
        ok(f"channel {channel}")
    else:
        fail(f"invalid channel: {channel!r}")

    git_sha = data.get("git_sha")
    if isinstance(git_sha, str) and git_sha:
        ok("git_sha present")
    else:
        fail("git_sha missing or empty")

    git_tag = data.get("git_tag")
    if git_tag is None or (isinstance(git_tag, str) and git_tag.startswith("v")):
        ok("git_tag shape OK")
    else:
        fail(f"invalid git_tag: {git_tag!r}")

    artifacts = data.get("artifacts")
    if not isinstance(artifacts, list):
        fail("artifacts must be a list")
        artifacts = []

    if artifacts:
        ok(f"artifacts count={len(artifacts)}")
    else:
        fail("artifacts list empty")

    for item in artifacts:
        if not isinstance(item, dict):
            fail("artifact entry must be object")
            continue
        name = item.get("name", "")
        if not (isinstance(name, str) and name.startswith("StrawWU-") and name.endswith(".iso")):
            fail(f"artifact name invalid: {name!r}")
        digest = item.get("sha256", "")
        if not (isinstance(digest, str) and SHA256_RE.match(digest)):
            fail(f"artifact sha256 invalid for {name}")
        size = item.get("size")
        if not isinstance(size, int) or size <= 0:
            fail(f"artifact size invalid for {name}")
        gpg_sig = item.get("gpg_sig")
        if gpg_sig is not None and not (isinstance(gpg_sig, str) and gpg_sig.endswith(".asc")):
            fail(f"artifact gpg_sig invalid for {name}")

    packages = data.get("packages")
    if isinstance(packages, list) and packages:
        ok(f"packages count={len(packages)}")
        for pkg in packages[:3]:
            if not isinstance(pkg, dict) or "name" not in pkg or "version" not in pkg:
                fail("package entry must have name+version")
                break
        else:
            ok("package entries shape OK")
    else:
        fail("packages list empty")

    boot_test = data.get("boot_test")
    if isinstance(boot_test, dict) and "bios" in boot_test and "uefi" in boot_test:
        ok("boot_test object present")
    else:
        fail("boot_test missing bios/uefi")

    published_at = data.get("published_at")
    if isinstance(published_at, str) and "T" in published_at and published_at.endswith("Z"):
        ok("published_at ISO8601 UTC")
    else:
        fail(f"published_at invalid: {published_at!r}")


def main() -> int:
    manifest_arg = sys.argv[1] if len(sys.argv) > 1 else str(REPO_ROOT / "os-image/output/release-manifest.json")
    expect = sys.argv[2] if len(sys.argv) > 2 else VERSION
    path = Path(manifest_arg)

    print("=== W7-RE1 release-manifest validation ===")
    validate_manifest(path, expect_version=expect)

    if FAILURES:
        print(f"=== validation done: FAIL ({len(FAILURES)} issue(s)) ===", file=sys.stderr)
        return 1
    print("=== validation done: PASS ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

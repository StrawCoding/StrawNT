#!/usr/bin/env python3
"""Validate StrawWU APT repository layout (RE3)."""
from __future__ import annotations

import gzip
import sys
from pathlib import Path

FAILURES: list[str] = []


def ok(msg: str) -> None:
    print(f"PASS: {msg}")


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"FAIL: {msg}")


def validate(repo_dir: Path, suite: str, arch: str, component: str, expect_signed: bool) -> int:
    dist = repo_dir / "dists" / suite
    binary = dist / component / f"binary-{arch}"
    packages_gz = binary / "Packages.gz"
    release = dist / "Release"
    release_gpg = dist / "Release.gpg"

    if not repo_dir.is_dir():
        fail(f"repo dir missing: {repo_dir}")
        return 1

    if not packages_gz.is_file():
        fail(f"Packages.gz missing: {packages_gz}")
    else:
        ok("Packages.gz present")
        try:
            data = gzip.decompress(packages_gz.read_bytes()).decode("utf-8", errors="replace")
            if "Package: " in data:
                ok("Packages.gz contains Package entries")
            else:
                fail("Packages.gz has no Package entries")
        except OSError as exc:
            fail(f"Packages.gz unreadable: {exc}")

    if not release.is_file():
        fail(f"Release missing: {release}")
    else:
        ok("Release present")
        text = release.read_text(encoding="utf-8", errors="replace")
        for field in ("Origin:", "Label:", "Suite:", "Codename:", "Architectures:", "MD5Sum:", "SHA256:"):
            if field in text:
                ok(f"Release contains {field}")
            else:
                fail(f"Release missing {field}")

    pool = repo_dir / "pool"
    debs = list(pool.rglob("*.deb"))
    if debs:
        ok(f"pool contains {len(debs)} .deb file(s)")
    else:
        fail("pool has no .deb files")

    if expect_signed:
        if release_gpg.is_file():
            ok("Release.gpg present")
        else:
            fail("Release.gpg missing (signed repo expected)")
    elif release_gpg.is_file():
        ok("Release.gpg present (optional)")
    else:
        ok("Release.gpg absent (unsigned allowed)")

    if FAILURES:
        print(f"\n=== validate-apt-repo: {len(FAILURES)} failure(s) ===", file=sys.stderr)
        return 1
    print("=== validate-apt-repo: PASS ===")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} REPO_DIR [suite] [arch] [component] [signed=1]", file=sys.stderr)
        return 2
    repo = Path(sys.argv[1])
    suite = sys.argv[2] if len(sys.argv) > 2 else "resolute"
    arch = sys.argv[3] if len(sys.argv) > 3 else "amd64"
    component = sys.argv[4] if len(sys.argv) > 4 else "main"
    signed = (sys.argv[5] if len(sys.argv) > 5 else "1") not in ("0", "false", "no")
    return validate(repo, suite, arch, component, signed)


if __name__ == "__main__":
    sys.exit(main())

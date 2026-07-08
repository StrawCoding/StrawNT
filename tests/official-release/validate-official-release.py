#!/usr/bin/env python3
"""Validate StrawWU official release DoD (official-release stage 8/8)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.version_policy import check_version_policy, official_release_authorized

REPO_ROOT = Path(__file__).resolve().parents[2]
CLOSEOUT_DIR = REPO_ROOT / "docs" / "plans" / "official-release"
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()
FAILURES: list[str] = []


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"FAIL: {msg}", file=sys.stderr)


def ok(msg: str) -> None:
    print(f"PASS: {msg}")


def require_file(path: Path, label: str) -> None:
    if path.is_file():
        ok(label)
    else:
        fail(f"{label} (missing {path})")


def main() -> int:
    print("=== official-release validation ===")

    require_file(CLOSEOUT_DIR / "official-release-dod.md", "official-release-dod.md")
    require_file(REPO_ROOT / ".official-release-authorized", ".official-release-authorized")
    require_file(REPO_ROOT / ".official-release-target", ".official-release-target")

    if official_release_authorized(REPO_ROOT):
        ok("official release authorization marker present")
    else:
        fail("missing .official-release-authorized")

    policy_ok, policy_msg = check_version_policy(REPO_ROOT, VERSION)
    if policy_ok:
        ok(policy_msg)
    else:
        fail(policy_msg)

    target = (REPO_ROOT / ".official-release-target").read_text(encoding="utf-8").splitlines()[0].strip()
    if target.startswith("1.0.0"):
        ok(f"release target: {target}")
    else:
        fail(f"unexpected .official-release-target: {target}")

    iso = REPO_ROOT / "os-image" / "output" / f"StrawWU-{VERSION}-amd64.iso"
    if iso.is_file():
        ok(f"ISO artifact: {iso.name} ({iso.stat().st_size} bytes)")
    else:
        fail(f"ISO missing: {iso}")

    for sums in (REPO_ROOT / "SHA256SUMS", REPO_ROOT / "os-image" / "output" / "SHA256SUMS"):
        if sums.is_file():
            ok(f"checksums: {sums.relative_to(REPO_ROOT)}")
        else:
            fail(f"missing {sums.relative_to(REPO_ROOT)}")

    html_report = CLOSEOUT_DIR / "html" / "official-release-report.html"
    if html_report.is_file():
        text = html_report.read_text(encoding="utf-8")
        if "hermes-deliver" in text and "#14b8a6" in text:
            ok("HTML hermes-deliver report")
        else:
            fail("HTML missing hermes-deliver or Teal theme")
    else:
        fail(f"missing {html_report}")

    ci = REPO_ROOT / ".github" / "workflows" / "release.yml"
    if ci.is_file():
        ok("CI release workflow")
    else:
        fail("missing .github/workflows/release.yml")

    if FAILURES:
        print(f"=== official-release validation: FAIL ({len(FAILURES)} issues) ===", file=sys.stderr)
        return 1
    print("=== official-release validation: PASS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

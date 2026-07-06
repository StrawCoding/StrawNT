#!/usr/bin/env python3
"""Validate StrawWU handbook documentation (W8-DOC-handbook)."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HANDBOOK = REPO_ROOT / "docs" / "user" / "handbook"
USER_DOCS = REPO_ROOT / "docs" / "user"
RENDER = REPO_ROOT / "tests" / "handbook" / "render-html.py"
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


def require_in_text(path: Path, patterns: list[str], label: str) -> None:
    text = path.read_text(encoding="utf-8")
    for pat in patterns:
        if re.search(pat, text, re.IGNORECASE | re.MULTILINE):
            ok(f"{label}: {pat}")
        else:
            fail(f"{label} missing pattern: {pat}")


def main() -> int:
    print("=== W8-DOC handbook validation ===")

    index = HANDBOOK / "README.md"
    user_md = HANDBOOK / "user-handbook.md"
    admin_md = HANDBOOK / "admin-handbook.md"
    wincompat_md = HANDBOOK / "wincompat-guide.md"
    upgrade_md = HANDBOOK / "upgrade-rescue-guide.md"
    manifest = HANDBOOK / "manifest.json"

    for p, label in [
        (index, "docs/user/handbook/README.md"),
        (user_md, "docs/user/handbook/user-handbook.md"),
        (admin_md, "docs/user/handbook/admin-handbook.md"),
        (wincompat_md, "docs/user/handbook/wincompat-guide.md"),
        (upgrade_md, "docs/user/handbook/upgrade-rescue-guide.md"),
        (manifest, "docs/user/handbook/manifest.json"),
        (RENDER, "tests/handbook/render-html.py"),
    ]:
        require_file(p, label)

    require_in_text(
        index,
        [
            r"user-handbook\.md",
            r"admin-handbook\.md",
            r"wincompat-guide\.md",
            r"upgrade-rescue-guide\.md",
            r"TBD",
        ],
        "handbook index",
    )

    require_in_text(
        user_md,
        [
            r"strawwu-shell",
            r"strawwu-hub",
            r"Flathub",
            r"strawwu-bug-report",
            r"fcitx5",
            r"strawwu-firstboot",
        ],
        "user-handbook",
    )

    require_in_text(
        admin_md,
        [
            r"strawwu-initd",
            r"strawwu-target-setup",
            r"release-iso",
            r"strawwu-initramfs-hooks",
            r"strawwu-keyring",
        ],
        "admin-handbook",
    )

    require_in_text(
        wincompat_md,
        [
            r"compat",
            r"A/B/C/F|等級",
            r"strawwu status",
            r"native",
            r"anticheat|反作弊",
        ],
        "wincompat-guide",
    )

    require_in_text(
        upgrade_md,
        [
            r"rollback",
            r"strawwu-upgrade",
            r"UPG",
            r"chroot",
            r"strawwu-initd repair",
        ],
        "upgrade-rescue-guide",
    )

    parent_readme = USER_DOCS / "README.md"
    if parent_readme.is_file():
        text = parent_readme.read_text(encoding="utf-8")
        if re.search(r"handbook", text, re.IGNORECASE):
            ok("docs/user/README.md links handbook")
        else:
            fail("docs/user/README.md missing handbook link")
    else:
        fail("docs/user/README.md missing")

    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if data.get("schema") != "strawwu-handbook-manifest/v1":
            fail(f"manifest schema={data.get('schema')!r}")
        else:
            ok("manifest schema v1")
        volumes = data.get("volumes", [])
        if len(volumes) < 4:
            fail("manifest volumes < 4")
        else:
            ok("manifest has 4 handbook volumes")
        if data.get("support", {}).get("community_url") != "TBD":
            fail("manifest community_url must be TBD (deferred scope)")
        else:
            ok("manifest community TBD placeholder")
    except json.JSONDecodeError as exc:
        fail(f"manifest JSON: {exc}")

    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
    if "test-handbook:" in makefile:
        ok("Makefile test-handbook target")
    else:
        fail("Makefile missing test-handbook")

    if "test-handbook.sh" in makefile:
        ok("Makefile preflight includes handbook")
    else:
        fail("Makefile preflight missing test-handbook.sh")

    rc = subprocess.run([sys.executable, str(RENDER)], cwd=REPO_ROOT, check=False)
    if rc.returncode != 0:
        fail("render-html.py failed")
        return 1

    for html_name in (
        "user-handbook.html",
        "admin-handbook.html",
        "wincompat-guide.html",
        "upgrade-rescue-guide.html",
    ):
        html_path = HANDBOOK / "html" / html_name
        require_file(html_path, f"html/{html_name}")
        html = html_path.read_text(encoding="utf-8")
        for needle in ("#14b8a6", "StrawWU", VERSION):
            if needle in html:
                ok(f"{html_name} contains {needle!r}")
            else:
                fail(f"{html_name} missing {needle!r}")

    if FAILURES:
        print(f"=== W8-DOC handbook done: FAIL ({len(FAILURES)} issues) ===", file=sys.stderr)
        return 1

    print("=== W8-DOC handbook done: PASS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

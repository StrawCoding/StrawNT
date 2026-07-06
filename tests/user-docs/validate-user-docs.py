#!/usr/bin/env python3
"""Validate StrawWU user documentation (W6-DOC1)."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
USER_DOCS = REPO_ROOT / "docs" / "user"
RENDER = REPO_ROOT / "tests" / "user-docs" / "render-html.py"
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
    print("=== W6-DOC1 user-docs validation ===")

    index = USER_DOCS / "README.md"
    install_md = USER_DOCS / "install-guide.md"
    rescue_md = USER_DOCS / "rescue-guide.md"
    manifest = USER_DOCS / "manifest.json"

    for p, label in [
        (index, "docs/user/README.md"),
        (install_md, "docs/user/install-guide.md"),
        (rescue_md, "docs/user/rescue-guide.md"),
        (manifest, "docs/user/manifest.json"),
        (RENDER, "tests/user-docs/render-html.py"),
    ]:
        require_file(p, label)

    require_in_text(
        index,
        [r"install-guide\.md", r"rescue-guide\.md", r"TBD"],
        "index links",
    )

    require_in_text(
        install_md,
        [
            r"Live USB",
            r"安裝 StrawWU",
            r"firstboot",
            r"strawwu-bug-report",
            r"Calamares",
        ],
        "install-guide",
    )

    require_in_text(
        rescue_md,
        [
            r"strawwu-initd repair",
            r"strawwu-target-setup --repair-only",
            r"chroot",
            r"smoke-live",
            r"rollback",
        ],
        "rescue-guide",
    )

    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if data.get("schema") != "strawwu-user-docs-manifest/v1":
            fail(f"manifest schema={data.get('schema')!r}")
        else:
            ok("manifest schema v1")
        if len(data.get("guides", [])) < 2:
            fail("manifest guides < 2")
        else:
            ok("manifest has install + rescue guides")
        if data.get("support", {}).get("community_url") != "TBD":
            fail("manifest community_url must be TBD (deferred scope)")
        else:
            ok("manifest community TBD placeholder")
    except json.JSONDecodeError as exc:
        fail(f"manifest JSON: {exc}")

    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
    if "test-user-docs:" in makefile:
        ok("Makefile test-user-docs target")
    else:
        fail("Makefile missing test-user-docs")

    if "test-user-docs.sh" in makefile:
        ok("Makefile preflight includes user-docs")
    else:
        fail("Makefile preflight missing test-user-docs.sh")

    rc = subprocess.run([sys.executable, str(RENDER)], cwd=REPO_ROOT, check=False)
    if rc.returncode != 0:
        fail("render-html.py failed")
        return 1

    for html_name in ("install-guide.html", "rescue-guide.html"):
        html_path = USER_DOCS / "html" / html_name
        require_file(html_path, f"html/{html_name}")
        html = html_path.read_text(encoding="utf-8")
        for needle in ("#14b8a6", "StrawWU", VERSION):
            if needle in html:
                ok(f"{html_name} contains {needle!r}")
            else:
                fail(f"{html_name} missing {needle!r}")

    if FAILURES:
        print(f"=== W6-DOC1 user-docs done: FAIL ({len(FAILURES)} issues) ===", file=sys.stderr)
        return 1

    print("=== W6-DOC1 user-docs done: PASS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

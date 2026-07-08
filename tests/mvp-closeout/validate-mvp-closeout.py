#!/usr/bin/env python3
"""Validate StrawWU MVP closeout DoD (w8-mvp-closeout)."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.version_policy import check_version_policy

REPO_ROOT = Path(__file__).resolve().parents[2]
MVP_DIR = REPO_ROOT / "docs" / "plans" / "mvp-closeout"
STAGE_REPORTS = REPO_ROOT / "docs" / "plans" / "stage-reports"
BASELINES = REPO_ROOT / "docs" / "plans" / "baselines"
RENDER = REPO_ROOT / "tests" / "mvp-closeout" / "render-html.py"
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()

FAILURES: list[str] = []
WAVE_STAGE_COUNT = 47

MVP_BASELINES = [
    "legal-baseline.json",
    "nosnap-audit.json",
    "target-flathub-baseline.json",
    "desktop-baseline.json",
    "firstboot-baseline.json",
    "install-firstboot-e2e-baseline.json",
    "shell-baseline.json",
    "apps-page-baseline.json",
    "deep-uninstall-baseline.json",
    "wincompat-e2e-baseline.json",
    "installed-boot-baseline.json",
    "release-manifest-baseline.json",
    "apt-repo-baseline.json",
    "handbook-baseline.json",
    "wave-status.json",
]

PRD_PATTERNS = [
    (MVP_DIR / "mvp-dod.md", [r"Flathub", r"Snap", r"bug-reporter", r"firstboot", r"strawwu-shell", r"Registry", r"wincompat", r"release-iso"]),
]


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
    print("=== W8-MVP closeout validation ===")

    mvp_md = MVP_DIR / "mvp-dod.md"
    require_file(mvp_md, "docs/plans/mvp-closeout/mvp-dod.md")
    require_file(RENDER, "tests/mvp-closeout/render-html.py")
    require_file(REPO_ROOT / "docs" / "plans" / "kickoff" / "W8-MVP-closeout.md", "kickoff W8-MVP-closeout.md")
    require_file(REPO_ROOT / "docs" / "plans" / "strawwu-prd-v0.5.md", "strawwu-prd-v0.5.md")
    require_file(REPO_ROOT / "docs" / "plans" / "strawwu-deferred-scope.md", "strawwu-deferred-scope.md")

    for path, patterns in PRD_PATTERNS:
        require_in_text(path, patterns, "mvp-dod.md PRD coverage")

    policy_ok, policy_msg = check_version_policy(REPO_ROOT, VERSION)
    if policy_ok:
        ok(policy_msg)
    else:
        fail(policy_msg)

    for name in MVP_BASELINES:
        require_file(BASELINES / name, f"baseline {name}")

    wave = json.loads((BASELINES / "wave-status.json").read_text(encoding="utf-8"))
    total = wave.get("total", 0)
    stages = wave.get("stages") or []
    if total != WAVE_STAGE_COUNT:
        fail(f"wave-status total expected {WAVE_STAGE_COUNT} got {total}")
    else:
        ok(f"wave-status total={WAVE_STAGE_COUNT}")
    if len(stages) != WAVE_STAGE_COUNT:
        fail(f"wave-status stages count expected {WAVE_STAGE_COUNT} got {len(stages)}")
    else:
        ok(f"wave-status stages count={WAVE_STAGE_COUNT}")

    passed = sum(1 for s in stages if s.get("pass"))
    ok(f"wave-status passed={passed}/{total} (closeout pending Hermes mark)")

    reports = sorted(STAGE_REPORTS.glob("*-report.md"))
    if len(reports) < WAVE_STAGE_COUNT - 1:
        fail(f"stage reports expected >= {WAVE_STAGE_COUNT - 1} got {len(reports)}")
    else:
        ok(f"stage reports count={len(reports)}")

    closeout_report = STAGE_REPORTS / "W8-MVP-closeout-report.md"
    require_file(closeout_report, "W8-MVP-closeout-report.md")

    result = subprocess.run([sys.executable, str(RENDER)], cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"render-html.py failed: {result.stderr.strip()}")
    else:
        for line in result.stdout.strip().splitlines():
            ok(line.replace("PASS: ", "render: "))

    html_path = MVP_DIR / "html" / "mvp-closeout-report.html"
    require_file(html_path, "mvp-closeout HTML report")
    html_text = html_path.read_text(encoding="utf-8")
    if "#14b8a6" in html_text:
        ok("HTML Teal accent #14b8a6")
    else:
        fail("HTML missing Teal accent #14b8a6")
    if "hermes-deliver" in html_text:
        ok("HTML hermes-deliver marker")
    else:
        fail("HTML missing hermes-deliver marker")

    post_mvp = REPO_ROOT / "docs" / "plans" / "kickoff" / "POST-MVP-AUTO-SEQUENCE.md"
    require_file(post_mvp, "POST-MVP-AUTO-SEQUENCE.md")
    if "u26-m1-base-clone" in post_mvp.read_text(encoding="utf-8"):
        ok("Post-MVP u26 transition documented")
    else:
        fail("POST-MVP-AUTO-SEQUENCE missing u26-m1-base-clone")

    if FAILURES:
        print(f"=== W8-MVP closeout validation: FAIL ({len(FAILURES)} issues) ===", file=sys.stderr)
        return 1
    print("=== W8-MVP closeout validation: PASS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

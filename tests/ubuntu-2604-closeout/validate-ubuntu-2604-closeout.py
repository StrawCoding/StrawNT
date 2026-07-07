#!/usr/bin/env python3
"""Validate StrawWU Ubuntu 26.04 migration closeout (u26-m7-closeout)."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CLOSEOUT_DIR = REPO_ROOT / "docs" / "plans" / "ubuntu-2604-closeout"
STAGE_REPORTS = REPO_ROOT / "docs" / "plans" / "stage-reports"
BASELINES = REPO_ROOT / "docs" / "plans" / "baselines"
RENDER = REPO_ROOT / "tests" / "ubuntu-2604-closeout" / "render-html.py"
STATUS_PATH = BASELINES / "ubuntu-2604-status.json"
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()

FAILURES: list[str] = []

U26_STAGES = [
    ("u26-m1-base-clone", "test-u26-base-clone"),
    ("u26-m2-kernel-rebase", "test-u26-kernel-rebase"),
    ("u26-m3-debs-rebuild", "test-u26-debs-rebuild"),
    ("u26-m4-suite-migrate", "test-u26-suite-migrate"),
    ("u26-m5-techrefs-refresh", "test-u26-techrefs-refresh"),
    ("u26-m6-regression-e2e", "test-u26-regression-e2e"),
    ("u26-m7-closeout", None),
]

STAGE_REPORTS_EXPECTED = [
    "U26-M1-base-clone-report.md",
    "U26-M2-kernel-rebase-report.md",
    "U26-M3-debs-rebuild-report.md",
    "U26-M4-suite-migrate-report.md",
    "U26-M5-techrefs-refresh-report.md",
    "U26-M6-regression-e2e-report.md",
    "U26-M7-closeout-report.md",
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


def run_make(target: str) -> bool:
    proc = subprocess.run(
        ["make", target],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        tail = (proc.stdout + proc.stderr).strip().splitlines()[-5:]
        fail(f"make {target} failed:\n" + "\n".join(tail))
        return False
    ok(f"make {target}")
    return True


def write_status(rows: list[dict]) -> None:
    passed = sum(1 for r in rows if r["pass"])
    failed = sum(1 for r in rows if not r["pass"])
    report = {
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "target": "26.04.0-resolute",
        "version": VERSION,
        "evidence_version": os.environ.get("STRAWWU_U26_EVIDENCE_VERSION", VERSION),
        "total": len(rows),
        "passed": passed,
        "failed": failed,
        "all_pass": failed == 0,
        "note": "Auto-updated by make test-ubuntu-2604-all-pass",
        "stages": rows,
    }
    STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATUS_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    ok(f"ubuntu-2604-status.json {passed}/{len(rows)} PASS")


def load_status_rows() -> list[dict] | None:
    if not STATUS_PATH.is_file():
        return None
    data = json.loads(STATUS_PATH.read_text(encoding="utf-8"))
    stages = data.get("stages") or []
    return stages or None


def run_stage_gates() -> list[dict]:
    rows: list[dict] = []
    for sid, make_target in U26_STAGES:
        if make_target:
            passed = run_make(make_target)
            rows.append({"id": sid, "status": "PASS" if passed else "FAIL", "pass": passed})
        else:
            closeout_report = STAGE_REPORTS / "U26-M7-closeout-report.md"
            passed = closeout_report.is_file()
            if passed:
                ok("U26-M7-closeout-report.md")
            else:
                fail("U26-M7-closeout-report.md missing")
            rows.append({"id": sid, "status": "PASS" if passed else "PENDING", "pass": passed})
    return rows


def verify_artifacts() -> None:
    for name in STAGE_REPORTS_EXPECTED:
        require_file(STAGE_REPORTS / name, name)

    result = subprocess.run([sys.executable, str(RENDER)], cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"render-html.py failed: {result.stderr.strip()}")
    else:
        for line in result.stdout.strip().splitlines():
            ok(line.replace("PASS: ", "render: "))

    html_path = CLOSEOUT_DIR / "html" / "ubuntu-2604-closeout-report.html"
    require_file(html_path, "ubuntu-2604-closeout HTML report")
    html_text = html_path.read_text(encoding="utf-8")
    if "#14b8a6" in html_text:
        ok("HTML Teal accent #14b8a6")
    else:
        fail("HTML missing Teal accent #14b8a6")
    if "hermes-deliver" in html_text:
        ok("HTML hermes-deliver marker")
    else:
        fail("HTML missing hermes-deliver marker")

    post = REPO_ROOT / "docs" / "plans" / "kickoff" / "POST-MVP-AUTO-SEQUENCE.md"
    if post.is_file() and "post-d1-strawwu-drivers" in post.read_text(encoding="utf-8"):
        ok("Post-MVP post-d1 transition documented")
    else:
        fail("POST-MVP-AUTO-SEQUENCE missing post-d1-strawwu-drivers")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skip-stage-tests",
        action="store_true",
        help="Use frozen ubuntu-2604-status.json (post VERSION bump)",
    )
    args = parser.parse_args()

    print("=== Ubuntu 26.04 migration closeout validation ===")

    require_file(CLOSEOUT_DIR / "ubuntu-2604-dod.md", "ubuntu-2604-dod.md")
    require_file(RENDER, "render-html.py")
    require_file(REPO_ROOT / "docs" / "plans" / "kickoff" / "U26-M7-closeout.md", "kickoff U26-M7-closeout.md")
    require_file(REPO_ROOT / "docs" / "plans" / "strawwu-ubuntu-2604-migration-plan.md", "migration plan")

    if not re.match(r"^0\.\d+\.\d+\.\d+$", VERSION):
        fail(f"VERSION semver MAJOR must be 0 before 1.0.0: {VERSION}")
    else:
        ok(f"VERSION MAJOR=0 policy: {VERSION}")

    target = json.loads((REPO_ROOT / "docs" / "plans" / "ubuntu-base-target.json").read_text(encoding="utf-8"))
    if target.get("active", {}).get("codename") != "resolute":
        fail(f"active codename not resolute: {target.get('active')}")
    else:
        ok(f"active base {target['active']['version']} resolute")

    verify_artifacts()

    if args.skip_stage_tests:
        rows = load_status_rows()
        if not rows or not all(r.get("pass") for r in rows):
            fail("ubuntu-2604-status.json missing or not all PASS (run without --skip-stage-tests first)")
        else:
            ok("frozen ubuntu-2604-status.json all stages PASS")
    else:
        rows = run_stage_gates()
        write_status(rows)

    if FAILURES:
        print(f"=== Ubuntu 26.04 closeout validation: FAIL ({len(FAILURES)} issues) ===", file=sys.stderr)
        return 1
    print("=== Ubuntu 26.04 closeout validation: PASS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

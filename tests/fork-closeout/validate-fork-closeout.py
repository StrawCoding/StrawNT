#!/usr/bin/env python3
"""Validate StrawWU Fork migration closeout (fork-f7-closeout)."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CLOSEOUT_DIR = REPO_ROOT / "docs" / "plans" / "fork-closeout"
STAGE_REPORTS = REPO_ROOT / "docs" / "plans" / "stage-reports"
BASELINES = REPO_ROOT / "docs" / "plans" / "baselines"
RENDER = REPO_ROOT / "tests" / "fork-closeout" / "render-html.py"
STATUS_PATH = BASELINES / "fork-status.json"
TARGET_PATH = REPO_ROOT / "docs" / "plans" / "ubuntu-base-target.json"
MANIFEST_PATH = REPO_ROOT / "os-image" / "fork-base" / "manifest.json"
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()

FAILURES: list[str] = []

FORK_STAGES = [
    ("fork-f1-baseline-snapshot", "test-fork-f1-baseline-snapshot"),
    ("fork-f2-manifest-repo", "test-fork-f2-manifest-repo"),
    ("fork-f3-build-pipeline", "test-fork-f3-build-pipeline"),
    ("fork-f4-package-overlays", "test-fork-f4-package-overlays"),
    ("fork-f5-apt-fork-suite", "test-fork-f5-apt-fork-suite"),
    ("fork-f6-regression-e2e", "test-fork-f6-regression-e2e"),
    ("fork-f7-closeout", None),
]

STAGE_REPORTS_EXPECTED = [
    "FORK-F1-baseline-snapshot-report.md",
    "FORK-F2-manifest-repo-report.md",
    "FORK-F3-build-pipeline-report.md",
    "FORK-F4-package-overlays-report.md",
    "FORK-F5-apt-fork-suite-report.md",
    "FORK-F6-regression-e2e-report.md",
    "FORK-F7-closeout-report.md",
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


def verify_base_mode_fork() -> None:
    target = json.loads(TARGET_PATH.read_text(encoding="utf-8"))
    if target.get("base_mode") != "fork":
        fail(f"base_mode not fork: {target.get('base_mode')!r}")
    else:
        ok("ubuntu-base-target.json base_mode=fork")

    env_script = REPO_ROOT / "os-image" / "scripts" / "lib" / "ubuntu-base-env.sh"
    proc = subprocess.run(
        ["bash", "-c", f"source {env_script} && load_ubuntu_base_env {REPO_ROOT} && echo $STRAWWU_BASE_MODE"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0 or proc.stdout.strip() != "fork":
        fail(f"STRAWWU_BASE_MODE resolves to {proc.stdout.strip()!r}, expected fork")
    else:
        ok("STRAWWU_BASE_MODE resolves to fork")


def verify_manifest_active() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if manifest.get("status") != "active":
        fail(f"fork-base manifest status not active: {manifest.get('status')!r}")
    else:
        ok("fork-base manifest status=active")


def verify_artifacts() -> None:
    for name in STAGE_REPORTS_EXPECTED:
        require_file(STAGE_REPORTS / name, name)

    result = subprocess.run([sys.executable, str(RENDER)], cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"render-html.py failed: {result.stderr.strip()}")
    else:
        for line in result.stdout.strip().splitlines():
            ok(line.replace("PASS: ", "render: "))

    html_path = CLOSEOUT_DIR / "html" / "fork-closeout-report.html"
    require_file(html_path, "fork-closeout HTML report")
    html_text = html_path.read_text(encoding="utf-8")
    if "#14b8a6" in html_text:
        ok("HTML Teal accent #14b8a6")
    else:
        fail("HTML missing Teal accent #14b8a6")
    if "hermes-deliver" in html_text:
        ok("HTML hermes-deliver marker")
    else:
        fail("HTML missing hermes-deliver marker")
    if "base_mode=fork" in html_text:
        ok("HTML base_mode=fork marker")
    else:
        fail("HTML missing base_mode=fork marker")

    post = REPO_ROOT / "docs" / "plans" / "kickoff" / "POST-MVP-AUTO-SEQUENCE.md"
    if post.is_file() and "post-d1-strawwu-drivers" in post.read_text(encoding="utf-8"):
        ok("Post-MVP post-d1 transition documented")
    else:
        fail("POST-MVP-AUTO-SEQUENCE missing post-d1-strawwu-drivers")


def run_stage_gates() -> list[dict]:
    rows: list[dict] = []
    for sid, make_target in FORK_STAGES:
        if make_target:
            passed = run_make(make_target)
            rows.append({"id": sid, "status": "PASS" if passed else "FAIL", "pass": passed})
        else:
            closeout_report = STAGE_REPORTS / "FORK-F7-closeout-report.md"
            passed = closeout_report.is_file()
            if passed:
                ok("FORK-F7-closeout-report.md")
            else:
                fail("FORK-F7-closeout-report.md missing")
            rows.append({"id": sid, "status": "PASS" if passed else "PENDING", "pass": passed})
    return rows


def write_status(rows: list[dict]) -> None:
    stages = {r["id"]: {"status": "PASS" if r["pass"] else "FAIL"} for r in rows}
    data = {
        "schema": "strawwu-fork-status/v1",
        "updated_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).strftime("%Y-%m-%d"),
        "pipeline": "fork_locked_sequence",
        "stages": stages,
    }
    STATUS_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    passed = sum(1 for r in rows if r["pass"])
    ok(f"fork-status.json {passed}/{len(rows)} PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skip-stage-tests",
        action="store_true",
        help="Skip per-stage make targets (use frozen fork-status.json)",
    )
    args = parser.parse_args()

    print("=== Fork migration closeout validation ===")

    require_file(CLOSEOUT_DIR / "fork-dod.md", "fork-dod.md")
    require_file(RENDER, "render-html.py")
    require_file(REPO_ROOT / "docs" / "plans" / "kickoff" / "FORK-F7-closeout.md", "kickoff FORK-F7-closeout.md")
    require_file(REPO_ROOT / "docs" / "plans" / "strawwu-fork-migration-plan.md", "fork migration plan")

    if not re.match(r"^0\.\d+\.\d+\.\d+$", VERSION):
        fail(f"VERSION semver MAJOR must be 0 before 1.0.0: {VERSION}")
    else:
        ok(f"VERSION MAJOR=0 policy: {VERSION}")

    verify_base_mode_fork()
    verify_manifest_active()
    verify_artifacts()

    if args.skip_stage_tests:
        if STATUS_PATH.is_file():
            data = json.loads(STATUS_PATH.read_text(encoding="utf-8"))
            stages = data.get("stages", {})
            if all(stages.get(sid, {}).get("status") == "PASS" for sid, _ in FORK_STAGES):
                ok("frozen fork-status.json all stages PASS")
            else:
                fail("fork-status.json not all PASS")
        else:
            fail("fork-status.json missing")
    else:
        rows = run_stage_gates()
        write_status(rows)

    if FAILURES:
        print(f"=== Fork closeout validation: FAIL ({len(FAILURES)} issues) ===", file=sys.stderr)
        return 1
    print("=== Fork closeout validation: PASS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

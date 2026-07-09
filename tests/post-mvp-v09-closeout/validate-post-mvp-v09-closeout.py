#!/usr/bin/env python3
"""Validate StrawWU Post-MVP v0.9 engineering closeout (post-v09-engineering-closeout)."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.version_policy import check_version_policy

REPO_ROOT = Path(__file__).resolve().parents[2]
CLOSEOUT_DIR = REPO_ROOT / "docs" / "plans" / "post-mvp-v09-closeout"
STAGE_REPORTS = REPO_ROOT / "docs" / "plans" / "stage-reports"
BASELINES = REPO_ROOT / "docs" / "plans" / "baselines"
RENDER = REPO_ROOT / "tests" / "post-mvp-v09-closeout" / "render-html.py"
STATUS_PATH = BASELINES / "post-mvp-status.json"
HERMES = Path(os.environ.get("HERMES_HOME", "/root/.hermes"))
HERMES_STATE = HERMES / "logs" / "task-workers" / "strawwu" / "state.json"
HERMES_CFG = HERMES / "config" / "task-workers" / "projects" / "strawwu.json"
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()

FAILURES: list[str] = []

V09_STAGES = [
    ("post-upg-rollback", "test-upgrade-rollback"),
    ("post-sec-secureboot-route", "test-secureboot-route"),
    ("post-sec-cve-policy", "test-sec-cve-policy"),
    ("post-perf-boot-regression", "test-perf-boot-regression"),
    ("post-ci-kernel-selfhosted", "test-ci-kernel-selfhosted"),
    ("post-w7-anticheat-substantive", "test-anticheat-substantive"),
    ("post-hw-t3-wincompat", "test-hw-t3-wincompat"),
    ("post-q8-golden-apps", "test-golden-apps"),
    ("post-hw5-stable-gate", "test-hw5-stable-gate"),
    ("post-backup-timeshift", "test-backup-timeshift"),
    ("post-v09-engineering-closeout", None),
]

V09_BASELINES = [
    "upgrade-rollback-baseline.json",
    "secureboot-route-baseline.json",
    "cve-policy-baseline.json",
    "boot-time-baseline.json",
    "ci-baseline.json",
    "anticheat-substantive-baseline.json",
    "hw-t3-wincompat-baseline.json",
    "golden-apps-launch-baseline.json",
    "hw5-stable-gate-baseline.json",
    "backup-timeshift-baseline.json",
]

STAGE_REPORTS_EXPECTED = [
    "POST-UPG-rollback-report.md",
    "POST-SEC-secureboot-route-report.md",
    "POST-SEC-cve-policy-report.md",
    "POST-PERF-boot-regression-report.md",
    "POST-CI-kernel-selfhosted-report.md",
    "POST-W7-anticheat-substantive-report.md",
    "POST-HW-T3-wincompat-report.md",
    "POST-Q8-golden-apps-report.md",
    "POST-HW5-stable-gate-report.md",
    "POST-BACKUP-timeshift-report.md",
    "POST-V09-engineering-closeout-report.md",
]

DOD_PATTERNS = [
    (CLOSEOUT_DIR / "post-mvp-v09-dod.md", [
        r"strawwu-upgrade",
        r"secureboot",
        r"cve-policy",
        r"boot-time",
        r"self-hosted",
        r"anticheat",
        r"golden-apps",
        r"hw5-stable",
        r"strawwu-backup",
        r"test-post-mvp-v09-closeout",
        r"test-post-mvp-all-pass",
    ]),
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


def _readable_file(p: Path) -> bool:
    # Path.is_file() re-raises EACCES (e.g. an unprivileged CI runner cannot even
    # traverse /root/.hermes). Treat any OSError as "not available" so host-only
    # orchestration paths never crash a repo validation.
    try:
        return p.is_file()
    except OSError:
        return False


def check_hermes_prerequisites() -> bool:
    if not _readable_file(HERMES_STATE):
        # Hermes worker state is host orchestration metadata under the operator's
        # $HOME/.hermes — absent/unreadable in CI and NOT a repo-verifiable
        # artifact. Skip the cross-check when unavailable instead of failing;
        # build hosts that have the state still enforce it fully.
        print(f"SKIP: Hermes state unavailable ({HERMES_STATE}) — orchestration cross-check skipped")
        return True
    state = json.loads(HERMES_STATE.read_text(encoding="utf-8"))
    stages = state.get("stages") or {}
    all_ok = True
    for sid, _ in V09_STAGES[:-1]:
        st = (stages.get(sid) or {}).get("status")
        if st == "PASS":
            ok(f"Hermes {sid} PASS")
        else:
            fail(f"Hermes {sid} status={st!r} (expected PASS)")
            all_ok = False
    return all_ok


def write_status(gate_rows: list[dict]) -> None:
    gate_by_id = {r["id"]: r for r in gate_rows}
    seq: list[str] = []
    if _readable_file(HERMES_CFG):
        seq = json.loads(HERMES_CFG.read_text(encoding="utf-8")).get("post_mvp_locked_sequence") or []
    if not seq:
        seq = [sid for sid, _ in V09_STAGES]

    hermes_stages: dict = {}
    if _readable_file(HERMES_STATE):
        hermes_stages = json.loads(HERMES_STATE.read_text(encoding="utf-8")).get("stages") or {}

    rows: list[dict] = []
    for sid in seq:
        if sid in gate_by_id:
            row = gate_by_id[sid]
            rows.append({"id": sid, "status": row["status"], "pass": row["pass"]})
        else:
            st = (hermes_stages.get(sid) or {}).get("status", "PENDING")
            rows.append({"id": sid, "status": st, "pass": st == "PASS"})

    passed = sum(1 for r in rows if r["pass"])
    failed = sum(1 for r in rows if not r["pass"])
    report = {
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "target": "0.9.0.0-engineering",
        "version": VERSION,
        "v09_target": "0.9.0.0-target",
        "total": len(rows),
        "passed": passed,
        "failed": failed,
        "all_pass": failed == 0,
        "note": "Auto-updated by validate-post-mvp-v09-closeout.py",
        "stages": rows,
    }
    STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATUS_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    v09_ids = {sid for sid, _ in V09_STAGES}
    v09_pass = sum(1 for r in rows if r["id"] in v09_ids and r["pass"])
    ok(f"post-mvp-status.json {passed}/{len(rows)} PASS (v0.9 subset {v09_pass}/11)")


def load_status_rows() -> list[dict] | None:
    if not STATUS_PATH.is_file():
        return None
    data = json.loads(STATUS_PATH.read_text(encoding="utf-8"))
    stages = data.get("stages") or []
    v09_ids = {sid for sid, _ in V09_STAGES[:-1]}
    subset = [s for s in stages if s.get("id") in v09_ids]
    return subset if len(subset) >= 10 else None


def run_stage_gates() -> list[dict]:
    rows: list[dict] = []
    for sid, make_target in V09_STAGES:
        if make_target:
            passed = run_make(make_target)
            rows.append({"id": sid, "status": "PASS" if passed else "FAIL", "pass": passed})
        else:
            closeout_report = STAGE_REPORTS / "POST-V09-engineering-closeout-report.md"
            passed = closeout_report.is_file()
            if passed:
                ok("POST-V09-engineering-closeout-report.md")
            else:
                fail("POST-V09-engineering-closeout-report.md missing")
            rows.append({"id": sid, "status": "PENDING" if not passed else "IN_PROGRESS", "pass": False})
    return rows


def verify_artifacts() -> None:
    for name in STAGE_REPORTS_EXPECTED[:-1]:
        require_file(STAGE_REPORTS / name, name)

    for name in V09_BASELINES:
        require_file(BASELINES / name, f"baseline {name}")

    hw_matrix = REPO_ROOT / "docs" / "plans" / "hw-matrix-results.json"
    require_file(hw_matrix, "hw-matrix-results.json")

    for path, patterns in DOD_PATTERNS:
        require_in_text(path, patterns, "post-mvp-v09-dod.md coverage")

    result = subprocess.run([sys.executable, str(RENDER)], cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"render-html.py failed: {result.stderr.strip()}")
    else:
        for line in result.stdout.strip().splitlines():
            ok(line.replace("PASS: ", "render: "))

    html_path = CLOSEOUT_DIR / "html" / "post-mvp-v09-closeout-report.html"
    require_file(html_path, "post-mvp-v09-closeout HTML report")
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
    if post.is_file() and "post-v09-engineering-closeout" in post.read_text(encoding="utf-8"):
        ok("Post-MVP post-v09-engineering-closeout terminal documented")
    else:
        fail("POST-MVP-AUTO-SEQUENCE missing post-v09-engineering-closeout")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skip-stage-tests",
        action="store_true",
        help="Use frozen post-mvp-status.json + Hermes state (post VERSION bump)",
    )
    args = parser.parse_args()

    print("=== Post-MVP v0.9 engineering closeout validation ===")

    require_file(CLOSEOUT_DIR / "post-mvp-v09-dod.md", "post-mvp-v09-dod.md")
    require_file(RENDER, "render-html.py")
    require_file(
        REPO_ROOT / "docs" / "plans" / "kickoff" / "POST-V09-engineering-closeout.md",
        "kickoff POST-V09-engineering-closeout.md",
    )
    require_file(REPO_ROOT / "docs" / "plans" / "strawwu-post-mvp-roadmap.md", "post-mvp roadmap")

    policy_ok, policy_msg = check_version_policy(REPO_ROOT, VERSION)
    if policy_ok:
        ok(policy_msg)
    else:
        fail(policy_msg)

    check_hermes_prerequisites()
    verify_artifacts()

    if args.skip_stage_tests:
        rows = load_status_rows()
        if not rows or len(rows) < 10:
            fail("post-mvp-status.json missing v0.9 stages (run without --skip-stage-tests first)")
        else:
            prereq_pass = all(r.get("pass") for r in rows)
            if prereq_pass:
                ok("frozen post-mvp-status.json prerequisite stages PASS")
            else:
                fail("post-mvp-status.json prerequisite stages not all PASS")
    else:
        rows = run_stage_gates()
        write_status(rows)

    if FAILURES:
        print(
            f"=== Post-MVP v0.9 closeout validation: FAIL ({len(FAILURES)} issues) ===",
            file=sys.stderr,
        )
        return 1
    print("=== Post-MVP v0.9 closeout validation: PASS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

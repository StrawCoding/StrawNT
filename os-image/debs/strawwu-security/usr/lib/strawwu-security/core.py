"""StrawWU CVE/USN policy — status, track, notify, preflight (fixture mode)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MANIFEST_PATH = Path("/usr/share/strawwu/security/security-manifest.yaml")
FIXTURE_PATH = Path("/usr/share/strawwu/security/fixture-catalog.json")
USN_FIXTURE_PATH = Path("/usr/share/strawwu/security/fixture-usn.json")
LOG_PATH = Path("/var/log/strawwu/security.log")
_PKG_USR = Path(__file__).resolve().parent.parent.parent
REPO_SCRIPTS = Path(__file__).resolve().parents[5] / "scripts" / "cve-policy"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def log_event(level: str, message: str, **fields: Any) -> None:
    entry = {"ts": utc_now(), "level": level, "msg": message, **fields}
    line = json.dumps(entry, ensure_ascii=False)
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        print(line, file=sys.stderr)


def fixture_path() -> Path:
    override = os.environ.get("STRAWWU_CVE_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "security" / "fixture-catalog.json"
    if dev.is_file():
        return dev
    return FIXTURE_PATH


def usn_fixture_path() -> Path:
    override = os.environ.get("STRAWWU_CVE_USN_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "security" / "fixture-usn.json"
    if dev.is_file():
        return dev
    return USN_FIXTURE_PATH


def use_fixture_mode() -> bool:
    return os.environ.get("STRAWWU_CVE_FIXTURE", "1") == "1"


def notify_enabled() -> bool:
    return os.environ.get("STRAWWU_CVE_NOTIFY", "0") == "1"


def read_fixture() -> dict[str, Any]:
    path = fixture_path()
    if not path.is_file():
        return {
            "schema": "strawwu-security-fixture/v1",
            "mock": True,
            "policy": {"ubuntu_series": "noble", "notify_enabled": False},
            "track": {"summary": {"total": 0}},
            "notify": {"dry_run": True},
            "preflight": {"ok": True, "issues": []},
        }
    return json.loads(path.read_text(encoding="utf-8"))


def read_usn_fixture() -> dict[str, Any]:
    path = usn_fixture_path()
    if path.is_file():
        return json.loads(path.read_text(encoding="utf-8"))
    return read_fixture().get("track", {})


def policy_status() -> dict[str, Any]:
    if use_fixture_mode():
        policy = read_fixture().get("policy", {})
        return {
            "schema": "strawwu-cve-status/v1",
            "ubuntu_series": policy.get("ubuntu_series", "noble"),
            "notify_enabled": bool(policy.get("notify_enabled", notify_enabled())),
            "fixture": True,
            "plan": policy.get("plan", "post-sec-cve-policy"),
            "doc": "docs/plans/kickoff/POST-SEC-cve-policy.md",
        }

    return {
        "schema": "strawwu-cve-status/v1",
        "ubuntu_series": "noble",
        "notify_enabled": notify_enabled(),
        "fixture": False,
        "plan": "post-sec-cve-policy",
        "doc": "docs/plans/kickoff/POST-SEC-cve-policy.md",
    }


def track_info() -> dict[str, Any]:
    if use_fixture_mode():
        track = read_usn_fixture()
        return {
            "schema": "strawwu-usn-track/v1",
            "mode": track.get("mode", "fixture"),
            "ubuntu_series": track.get("ubuntu_series", "noble"),
            "notices": track.get("notices", []),
            "summary": track.get("summary", {}),
            "dry_run": True,
            "doc": "docs/plans/kickoff/POST-SEC-cve-policy.md",
        }

    script = REPO_SCRIPTS / "track-usn.sh"
    if script.is_file():
        env = os.environ.copy()
        env.setdefault("STRAWWU_CVE_FIXTURE", "1")
        proc = subprocess.run(
            ["bash", str(script), "--json"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=60,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            try:
                data = json.loads(proc.stdout)
                data["dry_run"] = env.get("STRAWWU_CVE_FIXTURE", "1") == "1"
                return data
            except json.JSONDecodeError:
                pass

    return {
        "schema": "strawwu-usn-track/v1",
        "mode": "offline",
        "ubuntu_series": "noble",
        "notices": [],
        "summary": {"total": 0, "critical": 0, "high": 0, "needs_eval": 0},
        "dry_run": True,
    }


def notify_info() -> dict[str, Any]:
    if use_fixture_mode():
        notify = read_fixture().get("notify", {})
        track = read_usn_fixture()
        return {
            "schema": "strawwu-cve-notify/v1",
            "dry_run": bool(notify.get("dry_run", True)),
            "sent": bool(notify.get("sent", False)),
            "channel": notify.get("channel", "security-advisory"),
            "track_summary": track.get("summary", {}),
            "webhook_configured": bool(os.environ.get("STRAWWU_CVE_WEBHOOK_URL")),
        }

    return {
        "schema": "strawwu-cve-notify/v1",
        "dry_run": not notify_enabled(),
        "sent": False,
        "channel": "security-advisory",
        "track_summary": track_info().get("summary", {}),
        "webhook_configured": bool(os.environ.get("STRAWWU_CVE_WEBHOOK_URL")),
    }


def run_preflight() -> dict[str, Any]:
    issues: list[str] = []
    if use_fixture_mode():
        pf = read_fixture().get("preflight", {})
        return {
            "ok": bool(pf.get("ok", True)),
            "issues": list(pf.get("issues", [])),
            "notify_enabled": notify_enabled(),
            "fixture": True,
        }

    manifest = MANIFEST_PATH if MANIFEST_PATH.is_file() else (
        _PKG_USR / "share" / "strawwu" / "security" / "security-manifest.yaml"
    )
    if not manifest.is_file():
        issues.append("missing security-manifest.yaml")

    if notify_enabled() and not os.environ.get("STRAWWU_CVE_WEBHOOK_URL"):
        issues.append("STRAWWU_CVE_NOTIFY=1 but STRAWWU_CVE_WEBHOOK_URL unset")

    return {
        "ok": len(issues) == 0,
        "issues": issues,
        "notify_enabled": notify_enabled(),
        "fixture": False,
    }


def cmd_version() -> int:
    print("strawwu-security 0.7.0.0-target (skeleton)")
    return 0

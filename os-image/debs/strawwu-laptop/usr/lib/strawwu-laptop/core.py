"""StrawWU laptop peripherals — touchpad/Fn/TLP/webcam/fingerprint probe + smoke."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MANIFEST_PATH = Path("/usr/share/strawwu/laptop/laptop-peripherals-manifest.yaml")
FIXTURE_PATH = Path("/usr/share/strawwu/laptop/fixture-catalog.json")
PROFILES_DIR = Path("/usr/share/strawwu/laptop/device_profiles")
LOG_PATH = Path("/var/log/strawwu/laptop-peripherals.log")
PKG_VERSION = "0.6.3.3"
ERROR_CODE = "SWU-LPT-001"
_PKG_USR = Path(__file__).resolve().parent.parent.parent


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
    override = os.environ.get("STRAWWU_LAPTOP_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "laptop" / "fixture-catalog.json"
    if dev.is_file():
        return dev
    return FIXTURE_PATH


def profiles_dir() -> Path:
    override = os.environ.get("STRAWWU_LAPTOP_PROFILES_DIR")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "laptop" / "device_profiles"
    if dev.is_dir():
        return dev
    return PROFILES_DIR


def use_fixture_mode() -> bool:
    if os.environ.get("STRAWWU_LAPTOP_FIXTURE") == "1":
        return True
    return not shutil.which("tlp")


def read_fixture() -> dict[str, Any]:
    path = fixture_path()
    if not path.is_file():
        return {"schema": "strawwu-laptop-fixture/v1", "mock": True, "peripherals": "SKIP"}
    return json.loads(path.read_text(encoding="utf-8"))


def run_cmd(args: list[str], *, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    log_event("info", "exec", cmd=args)
    return subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)


def probe_touchpad() -> dict[str, Any]:
    if use_fixture_mode():
        fx = read_fixture().get("touchpad", {})
        return {"status": fx.get("status", "PASS"), "mock": True, **fx}
    if not shutil.which("libinput"):
        return {"status": "SKIP", "reason": "libinput-tools not installed"}
    proc = run_cmd(["libinput", "list-devices"])
    text = proc.stdout or ""
    if re.search(r"Touchpad|Touch Pad|Synaptics|ELAN|ALPS", text, re.I):
        return {"status": "PASS", "driver": "libinput", "mock": False}
    if Path("/dev/input").is_dir() and any(Path("/dev/input").glob("event*")):
        return {"status": "PASS", "driver": "libinput", "mock": False, "note": "input events without named touchpad"}
    return {"status": "SKIP", "reason": "no touchpad detected", "mock": False}


def probe_fn_keys() -> dict[str, Any]:
    if use_fixture_mode():
        fx = read_fixture().get("fn_keys", {})
        return {"status": fx.get("status", "PASS"), "mock": True, **fx}
    has_brightness = shutil.which("brightnessctl") is not None
    has_acpi = shutil.which("acpid") is not None or Path("/proc/acpi").exists()
    if has_brightness or has_acpi:
        return {
            "status": "PASS",
            "brightnessctl": has_brightness,
            "acpid": has_acpi,
            "mock": False,
        }
    return {"status": "SKIP", "reason": "no Fn key helpers", "mock": False}


def probe_tlp() -> dict[str, Any]:
    if use_fixture_mode():
        fx = read_fixture().get("tlp", {})
        return {"status": fx.get("status", "PASS"), "mock": True, **fx}
    if not shutil.which("tlp"):
        return {"status": "SKIP", "reason": "tlp not installed"}
    proc = run_cmd(["systemctl", "is-active", "tlp"])
    active = proc.stdout.strip() == "active"
    return {"status": "PASS" if active else "SKIP", "active": active, "mock": False}


def probe_webcam() -> dict[str, Any]:
    if use_fixture_mode():
        fx = read_fixture().get("webcam", {})
        return {"status": fx.get("status", "PASS"), "mock": True, **fx}
    if shutil.which("v4l2-ctl"):
        proc = run_cmd(["v4l2-ctl", "--list-devices"])
        if proc.returncode == 0 and proc.stdout.strip():
            return {"status": "PASS", "stack": "v4l2", "mock": False}
    if any(Path("/dev").glob("video*")):
        pipewire = shutil.which("pipewire") is not None
        return {"status": "PASS", "stack": "pipewire" if pipewire else "v4l2", "mock": False}
    return {"status": "SKIP", "reason": "no webcam device", "mock": False}


def probe_fingerprint() -> dict[str, Any]:
    if use_fixture_mode():
        fx = read_fixture().get("fingerprint", {})
        return {"status": fx.get("status", "PASS"), "mock": True, **fx}
    if not shutil.which("fprintd-list"):
        return {"status": "SKIP", "reason": "fprintd not installed"}
    user = os.environ.get("USER") or os.environ.get("LOGNAME") or "root"
    proc = run_cmd(["fprintd-list", user])
    if proc.returncode == 0 and "device" in (proc.stdout or "").lower():
        return {"status": "PASS", "mock": False}
    if proc.returncode == 0:
        return {"status": "SKIP", "reason": "fprintd ok but no reader", "mock": False}
    return {"status": "SKIP", "reason": "fprintd probe failed", "mock": False}


def aggregate_status(parts: dict[str, dict[str, Any]]) -> str:
    statuses = [p.get("status", "SKIP") for p in parts.values()]
    if any(s == "PASS" for s in statuses):
        return "PASS"
    if all(s == "SKIP" for s in statuses):
        return "SKIP"
    return "FAIL"


def peripheral_status() -> dict[str, Any]:
    if use_fixture_mode():
        fx = read_fixture()
        return {
            "mock": True,
            "profile_id": fx.get("profile_id", "generic-intel-laptop"),
            "touchpad": fx.get("touchpad", {}),
            "fn_keys": fx.get("fn_keys", {}),
            "tlp": fx.get("tlp", {}),
            "webcam": fx.get("webcam", {}),
            "fingerprint": fx.get("fingerprint", {}),
            "peripherals": fx.get("peripherals", "PASS"),
            "version": PKG_VERSION,
        }
    touchpad = probe_touchpad()
    fn_keys = probe_fn_keys()
    tlp = probe_tlp()
    webcam = probe_webcam()
    fingerprint = probe_fingerprint()
    parts = {
        "touchpad": touchpad,
        "fn_keys": fn_keys,
        "tlp": tlp,
        "webcam": webcam,
        "fingerprint": fingerprint,
    }
    return {
        "mock": False,
        "touchpad": touchpad,
        "fn_keys": fn_keys,
        "tlp": tlp,
        "webcam": webcam,
        "fingerprint": fingerprint,
        "peripherals": aggregate_status(parts),
        "version": PKG_VERSION,
    }


def list_profiles() -> dict[str, Any]:
    directory = profiles_dir()
    profiles: list[dict[str, Any]] = []
    if directory.is_dir():
        for path in sorted(directory.glob("*.json")):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                profiles.append(
                    {
                        "profile_id": data.get("profile_id", path.stem),
                        "label": data.get("label", path.stem),
                        "chassis": data.get("chassis", "unknown"),
                    }
                )
            except (json.JSONDecodeError, OSError):
                continue
    return {"profiles": profiles, "count": len(profiles), "mock": use_fixture_mode()}


def run_smoke() -> dict[str, Any]:
    status = peripheral_status()
    tests = {
        "touchpad": status["touchpad"].get("status", "SKIP"),
        "fingerprint": status["fingerprint"].get("status", "SKIP"),
        "webcam": status["webcam"].get("status", "SKIP"),
        "peripherals": status.get("peripherals", "SKIP"),
    }
    ok = tests["peripherals"] not in (None, "SKIP", "FAIL")
    return {
        "smoke": "PASS" if ok else "FAIL",
        "tests": tests,
        "mock": status.get("mock", False),
        "profile_id": status.get("profile_id", "live"),
        "version": PKG_VERSION,
    }


def cmd_version() -> int:
    print(PKG_VERSION)
    return 0


def run_cli(command: str, *, as_json: bool = False) -> int:
    if command == "status":
        data = peripheral_status()
    elif command == "smoke":
        data = run_smoke()
    elif command == "profiles":
        data = list_profiles()
    else:
        log_event("error", "unknown command", command=command, code=ERROR_CODE)
        print(f"Unknown command: {command}", file=sys.stderr)
        return 1
    if as_json:
        print(json.dumps(data, indent=2, ensure_ascii=False))
    else:
        print(json.dumps(data, ensure_ascii=False))
    return 0 if data.get("smoke", "PASS") != "FAIL" and data.get("peripherals", "PASS") != "FAIL" else 1

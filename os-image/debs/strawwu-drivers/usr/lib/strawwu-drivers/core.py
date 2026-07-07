"""StrawWU driver manager — ubuntu-drivers wrapper with fixture mode."""

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

MANIFEST_PATH = Path("/usr/share/strawwu/drivers/drivers-manifest.yaml")
FIXTURE_PATH = Path("/usr/share/strawwu/drivers/fixture-catalog.json")
LOG_PATH = Path("/var/log/strawwu/drivers.log")
POLKIT_ACTION = "xyz.wastebase.strawwu.drivers.install"
PKG_VERSION = "0.6.2.7"
ERROR_CODE = "SWU-DRV-001"
_PKG_USR = Path(__file__).resolve().parent.parent.parent

VENDOR_PATTERNS = {
    "nvidia": re.compile(r"\b(10de:|nvidia|geforce|quadro|tesla)\b", re.I),
    "amd": re.compile(r"\b(1002:|amd|radeon)\b", re.I),
    "intel": re.compile(r"\b(8086:|intel|iris|uhd)\b", re.I),
}


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
    override = os.environ.get("STRAWWU_DRIVERS_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "drivers" / "fixture-catalog.json"
    if dev.is_file():
        return dev
    return FIXTURE_PATH


def use_fixture_mode() -> bool:
    if os.environ.get("STRAWWU_DRIVERS_FIXTURE") == "1":
        return True
    return shutil.which("ubuntu-drivers") is None


def read_fixture() -> dict[str, Any]:
    path = fixture_path()
    if not path.is_file():
        return {"schema": "strawwu-drivers-fixture/v1", "mock": True, "devices": [], "drivers": []}
    return json.loads(path.read_text(encoding="utf-8"))


def run_cmd(args: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    log_event("info", "exec", cmd=args)
    return subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)


def detect_secure_boot() -> dict[str, Any]:
    if use_fixture_mode():
        sb = read_fixture().get("secure_boot", {})
        return {
            "enabled": bool(sb.get("enabled")),
            "state": sb.get("state", "unknown"),
            "warning": sb.get("warning", ""),
            "plan": sb.get("plan", "post-sec-secureboot-route"),
        }

    mokutil = shutil.which("mokutil")
    if not mokutil:
        return {"enabled": False, "state": "unknown", "warning": "", "plan": "post-sec-secureboot-route"}

    proc = run_cmd([mokutil, "--sb-state"])
    text = (proc.stdout + proc.stderr).strip().lower()
    enabled = "enabled" in text
    warning = ""
    if enabled:
        warning = (
            "Secure Boot is enabled. Proprietary NVIDIA kernel modules may require "
            "MOK enrollment before they load. See POST-SEC-secureboot-route."
        )
    return {
        "enabled": enabled,
        "state": "enabled" if enabled else "disabled",
        "warning": warning,
        "plan": "post-sec-secureboot-route",
    }


def classify_vendor(text: str) -> str:
    for vendor, pattern in VENDOR_PATTERNS.items():
        if pattern.search(text):
            return vendor
    return "unknown"


def parse_lspci_devices() -> list[dict[str, Any]]:
    lspci = shutil.which("lspci")
    if not lspci:
        return []

    proc = run_cmd([lspci, "-nn"])
    devices: list[dict[str, Any]] = []
    for line in proc.stdout.splitlines():
        if "VGA compatible controller" not in line and "3D controller" not in line:
            continue
        pci_id = ""
        match = re.search(r"\[([0-9a-f]{4}:[0-9a-f]{4})\]", line, re.I)
        if match:
            pci_id = match.group(1).lower()
        model = re.sub(r"^\S+:\s*", "", line).strip()
        devices.append(
            {
                "pci_id": pci_id,
                "vendor": classify_vendor(line),
                "model": model,
                "driver": "",
                "driver_label": "",
                "recommended": False,
                "installed": False,
                "status": "unknown",
            }
        )
    return devices


def parse_ubuntu_drivers_list() -> list[dict[str, Any]]:
    proc = run_cmd(["ubuntu-drivers", "list", "--gpgpu"])
    drivers: list[dict[str, Any]] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        package = line.split()[0]
        vendor = classify_vendor(package)
        drivers.append(
            {
                "package": package,
                "vendor": vendor,
                "label": package,
                "recommended": "recommended" in line.lower(),
                "installed": "installed" in line.lower(),
            }
        )
    return drivers


def parse_ubuntu_drivers_devices() -> list[dict[str, Any]]:
    proc = run_cmd(["ubuntu-drivers", "devices"])
    devices: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    for raw in proc.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("==" ) or line.startswith("model"):
            if current:
                devices.append(current)
            current = None
            continue
        if "pci id" in line.lower():
            pci_match = re.search(r"([0-9a-f]{4}:[0-9a-f]{4})", line, re.I)
            model = line.split(":", 1)[-1].strip()
            current = {
                "pci_id": pci_match.group(1).lower() if pci_match else "",
                "vendor": classify_vendor(line),
                "model": model,
                "driver": "",
                "driver_label": "",
                "recommended": False,
                "installed": False,
                "status": "unknown",
            }
            continue
        if current and "driver" in line.lower():
            pkg = line.split()[-1]
            current["driver"] = pkg
            current["driver_label"] = pkg
            current["recommended"] = "recommended" in line.lower()
            current["installed"] = "installed" in line.lower()
            current["status"] = "installed" if current["installed"] else "available"

    if current:
        devices.append(current)
    return devices


def list_drivers() -> dict[str, Any]:
    mock = use_fixture_mode()
    if mock:
        data = read_fixture()
        return {
            "mock": True,
            "drivers": data.get("drivers", []),
            "secure_boot": detect_secure_boot(),
        }

    drivers = parse_ubuntu_drivers_list()
    return {
        "mock": False,
        "drivers": drivers,
        "secure_boot": detect_secure_boot(),
    }


def driver_status() -> dict[str, Any]:
    mock = use_fixture_mode()
    if mock:
        data = read_fixture()
        return {
            "mock": True,
            "devices": data.get("devices", []),
            "drivers": data.get("drivers", []),
            "secure_boot": detect_secure_boot(),
        }

    devices = parse_ubuntu_drivers_devices()
    if not devices:
        devices = parse_lspci_devices()
    drivers = parse_ubuntu_drivers_list()
    return {
        "mock": False,
        "devices": devices,
        "drivers": drivers,
        "secure_boot": detect_secure_boot(),
    }


def install_driver(package: str, *, dry_run: bool = False) -> dict[str, Any]:
    if not package:
        raise ValueError("package name required")

    mock = use_fixture_mode()
    if mock:
        log_event("info", "mock install", package=package, dry_run=dry_run)
        return {
            "mock": True,
            "package": package,
            "success": True,
            "message": f"Simulated install of {package}",
            "dry_run": dry_run,
        }

    if dry_run:
        return {
            "mock": False,
            "package": package,
            "success": True,
            "message": f"Would install {package}",
            "dry_run": True,
        }

    pkexec = shutil.which("pkexec")
    if pkexec:
        proc = run_cmd([pkexec, "--action-id", POLKIT_ACTION, "ubuntu-drivers", "install", package], timeout=900)
    else:
        proc = run_cmd(["ubuntu-drivers", "install", package], timeout=900)

    success = proc.returncode == 0
    if not success:
        log_event("error", "install failed", package=package, stderr=proc.stderr.strip(), code=ERROR_CODE)
    return {
        "mock": False,
        "package": package,
        "success": success,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
        "returncode": proc.returncode,
    }


def cmd_version() -> int:
    print(PKG_VERSION)
    return 0


def emit(payload: dict[str, Any], *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(payload, ensure_ascii=False))


def run_cli(command: str | None, *, package: str = "", as_json: bool = False, dry_run: bool = False) -> int:
    try:
        if command in (None, "status"):
            emit(driver_status(), as_json=as_json)
            return 0
        if command == "list":
            emit(list_drivers(), as_json=as_json)
            return 0
        if command == "devices":
            status = driver_status()
            emit({"devices": status.get("devices", []), "mock": status.get("mock", False)}, as_json=as_json)
            return 0
        if command == "install":
            result = install_driver(package, dry_run=dry_run)
            emit(result, as_json=as_json)
            return 0 if result.get("success") else 1
        return 2
    except Exception as exc:  # noqa: BLE001 — CLI boundary
        log_event("error", "cli failure", error=str(exc), code=ERROR_CODE)
        if as_json:
            print(json.dumps({"success": False, "error": str(exc)}, ensure_ascii=False))
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 1

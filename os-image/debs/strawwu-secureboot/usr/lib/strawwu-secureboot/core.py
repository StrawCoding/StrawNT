"""StrawWU Secure Boot route — status, route doc, preflight (fixture mode)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MANIFEST_PATH = Path("/usr/share/strawwu/secureboot/secureboot-manifest.yaml")
FIXTURE_PATH = Path("/usr/share/strawwu/secureboot/fixture-catalog.json")
LOG_PATH = Path("/var/log/strawwu/secureboot.log")
_PKG_USR = Path(__file__).resolve().parent.parent.parent
REPO_SCRIPTS = Path(__file__).resolve().parents[5] / "scripts" / "secureboot-route"


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
    override = os.environ.get("STRAWWU_SECUREBOOT_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "secureboot" / "fixture-catalog.json"
    if dev.is_file():
        return dev
    return FIXTURE_PATH


def use_fixture_mode() -> bool:
    return os.environ.get("STRAWWU_SECUREBOOT_FIXTURE") == "1"


def mok_cert_path() -> Path | None:
    """Locate the StrawWU MOK PEM cert used to verify the signed kernel."""
    override = os.environ.get("STRAWWU_MOK_CERT")
    if override:
        return Path(override)
    for candidate in (
        Path("/usr/share/strawwu/secureboot/StrawWU-MOK.crt"),
        _PKG_USR / "share" / "strawwu" / "secureboot" / "StrawWU-MOK.crt",
    ):
        if candidate.is_file():
            return candidate
    return None


def read_fixture() -> dict[str, Any]:
    path = fixture_path()
    if not path.is_file():
        return {
            "schema": "strawwu-secureboot-fixture/v1",
            "mock": True,
            "secure_boot": {"enabled": False, "state": "unknown", "enforced": False},
            "route": {"boot_chain": [], "signed_kernel": False, "signed_initrd": False},
            "preflight": {"ok": True, "issues": []},
        }
    return json.loads(path.read_text(encoding="utf-8"))


def run_cmd(args: list[str], *, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    log_event("info", "exec", cmd=args)
    return subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)


def enforced() -> bool:
    return os.environ.get("STRAWWU_SECURE_BOOT_ENFORCE", "0") == "1"


def detect_sb_state() -> dict[str, Any]:
    if use_fixture_mode():
        sb = read_fixture().get("secure_boot", {})
        return {
            "enabled": bool(sb.get("enabled")),
            "state": sb.get("state", "unknown"),
            "enforced": bool(sb.get("enforced", enforced())),
            "warning": sb.get("warning", ""),
            "plan": sb.get("plan", "post-sec-secureboot-route"),
        }

    mokutil = shutil.which("mokutil")
    if not mokutil:
        return {
            "enabled": False,
            "state": "unknown",
            "enforced": enforced(),
            "warning": "",
            "plan": "post-sec-secureboot-route",
        }

    proc = run_cmd([mokutil, "--sb-state"])
    text = (proc.stdout + proc.stderr).strip().lower()
    enabled = "enabled" in text
    warning = ""
    if enabled and not enforced():
        warning = (
            "Secure Boot is enabled. StrawWU signed kernel/initrd route is documented "
            "(post-sec-secureboot-route) but not enforced in this release."
        )
    return {
        "enabled": enabled,
        "state": "enabled" if enabled else "disabled",
        "enforced": enforced(),
        "warning": warning,
        "plan": "post-sec-secureboot-route",
    }


def route_info() -> dict[str, Any]:
    if use_fixture_mode():
        route = read_fixture().get("route", {})
        return {
            "schema": "strawwu-secureboot-route/v1",
            "enforced": enforced(),
            "boot_chain": route.get("boot_chain", []),
            "signed_kernel": bool(route.get("signed_kernel")),
            "signed_initrd": bool(route.get("signed_initrd")),
            "shim_source": route.get("shim_source", "strawwu-skeleton"),
            "dry_run_signing": bool(route.get("dry_run_signing", True)),
            "doc": "docs/plans/kickoff/POST-SEC-secureboot-route.md",
        }

    # MOK single track: firmware trusts shim (MS UEFI CA), shim+grub stay
    # Canonical-signed, only the kernel carries the StrawWU MOK signature.
    boot_chain = [
        "uefi_firmware",
        "shim.efi",
        "grubx64.efi",
        "vmlinuz(mok-signed)",
        "initrd.img",
    ]
    boot_dir = Path(os.environ.get("STRAWWU_SB_BOOT_DIR", "/boot"))
    signed_kernel = False
    signed_initrd = False
    vmlinuz = boot_dir / "vmlinuz"
    initrd = boot_dir / "initrd.img"
    mok_cert = mok_cert_path()
    if vmlinuz.is_file() and shutil.which("sbverify"):
        # Verify specifically against the StrawWU MOK, not merely "any signature".
        if mok_cert and mok_cert.is_file():
            proc = run_cmd(["sbverify", "--cert", str(mok_cert), str(vmlinuz)])
        else:
            proc = run_cmd(["sbverify", str(vmlinuz)])
        signed_kernel = proc.returncode == 0
    if initrd.is_file():
        signed_initrd = (boot_dir / ".strawwu-sb-hashes.txt").is_file()

    return {
        "schema": "strawwu-secureboot-route/v1",
        "enforced": enforced(),
        "boot_chain": boot_chain,
        "signed_kernel": signed_kernel,
        "signed_initrd": signed_initrd,
        "shim_source": "canonical-shim",
        "mok_track": True,
        "dry_run_signing": os.environ.get("STRAWWU_SB_SIGN", "0") != "1",
        "doc": "docs/plans/kickoff/POST-SEC-secureboot-route.md",
    }


def run_preflight() -> dict[str, Any]:
    issues: list[str] = []
    if use_fixture_mode():
        pf = read_fixture().get("preflight", {})
        return {
            "ok": bool(pf.get("ok", True)),
            "issues": list(pf.get("issues", [])),
            "enforced": enforced(),
            "fixture": True,
        }

    if enforced():
        for tool in ("sbsign", "sbverify"):
            if not shutil.which(tool):
                issues.append(f"missing tool: {tool} (required when STRAWWU_SECURE_BOOT_ENFORCE=1)")

    boot_dir = Path(os.environ.get("STRAWWU_SB_BOOT_DIR", "/boot"))
    if enforced():
        for name in ("vmlinuz", "initrd.img"):
            if not (boot_dir / name).is_file():
                issues.append(f"missing boot artifact: {name}")

    return {
        "ok": len(issues) == 0,
        "issues": issues,
        "enforced": enforced(),
        "fixture": False,
    }


def read_manifest_version() -> str:
    """Read the build-stamped version from the secureboot manifest."""
    env = os.environ.get("STRAWWU_VERSION")
    if env:
        return env
    for path in (MANIFEST_PATH, _PKG_USR / "share" / "strawwu" / "secureboot" / "secureboot-manifest.yaml"):
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if stripped.startswith("version:"):
                    return stripped.split(":", 1)[1].strip()
        except OSError:
            continue
    return "unknown"


def cmd_version() -> int:
    print(f"strawwu-secureboot {read_manifest_version()}")
    return 0

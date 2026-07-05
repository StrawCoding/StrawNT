"""Create .strawwu-bug diagnostic bundles (local-only by default)."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from filter import redact_text

BUNDLE_FORMAT = "bundle.strawwu-bug"
BUNDLE_VERSION = 1

STRAWWU_LOG_DIR = Path("/var/log/strawwu")
LOG_NAMES = (
    "boot-selfcheck.log",
    "install.log",
    "target-setup.log",
    "firstboot.log",
    "app-registry.log",
    "update.log",
    "wincompat.log",
)


def _run_command(args: list[str], timeout: int = 30) -> str:
    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        output = (proc.stdout or "") + (proc.stderr or "")
        return output.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        return f"[unavailable: {exc}]"


def _machine_id_hash() -> str:
    mid_path = Path("/etc/machine-id")
    if not mid_path.is_file():
        return "unknown"
    digest = hashlib.sha256(mid_path.read_text(encoding="utf-8").strip().encode()).hexdigest()
    return digest[:16]


def _read_version() -> str:
    for path in (Path("/etc/strawwu/version"), Path("/usr/share/strawwu/VERSION")):
        if path.is_file():
            return path.read_text(encoding="utf-8").strip()
    env = os.environ.get("STRAWWU_VERSION", "")
    if env:
        return env.strip()
    return "unknown"


def _collect_journal() -> str:
    if shutil.which("journalctl"):
        raw = _run_command(
            [
                "journalctl",
                "--no-pager",
                "--since",
                "24 hours ago",
                "-u",
                "strawwu-*",
                "-o",
                "short-iso",
            ],
            timeout=60,
        )
        if raw and not raw.startswith("[unavailable"):
            return redact_text(raw)
        raw = _run_command(
            ["journalctl", "--no-pager", "--since", "24 hours ago", "-o", "short-iso"],
            timeout=60,
        )
        return redact_text(raw)
    return "[journalctl unavailable]"


def _collect_dmesg() -> str:
    if shutil.which("dmesg"):
        return redact_text(_run_command(["dmesg", "--ctime"], timeout=15))
    return "[dmesg unavailable]"


def _collect_lsblk() -> str:
    if shutil.which("lsblk"):
        return _run_command(["lsblk", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS"], timeout=10)
    return "[lsblk unavailable]"


def _collect_registry_summary() -> dict[str, Any] | None:
    registry = Path("/var/lib/strawwu/app-registry.json")
    if not registry.is_file():
        return None
    try:
        data = json.loads(registry.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"status": "unreadable"}
    apps = data.get("apps") if isinstance(data, dict) else None
    if not isinstance(apps, list):
        return {"status": "present", "app_count": 0}
    summary = []
    for app in apps[:50]:
        if not isinstance(app, dict):
            continue
        summary.append(
            {
                "id": app.get("id", "unknown"),
                "name": app.get("name", "unknown"),
                "protected": bool(app.get("protected", False)),
            }
        )
    return {"app_count": len(apps), "apps": summary}


def build_manifest(*, notes: str = "", upload_consent: bool = False) -> dict[str, Any]:
    return {
        "format": BUNDLE_FORMAT,
        "bundle_version": BUNDLE_VERSION,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "consent": {
            "upload_requested": upload_consent,
            "auto_upload_default": False,
        },
        "privacy": {
            "home_contents_included": False,
            "filtered_fields": [
                "password",
                "token",
                "secret",
                "ssh_keys",
                "ssid",
                "psk",
                "home_paths",
            ],
        },
        "user_notes": notes.strip(),
    }


def build_system_json() -> dict[str, Any]:
    uname = platform.uname()
    return {
        "strawwu_version": _read_version(),
        "kernel": uname.release,
        "machine": uname.machine,
        "hostname_hash": hashlib.sha256(uname.node.encode()).hexdigest()[:12],
        "machine_id_hash": _machine_id_hash(),
    }


def create_bundle(
    output_path: Path,
    *,
    notes: str = "",
    upload_consent: bool = False,
    dry_run: bool = False,
) -> Path:
    """Assemble a .strawwu-bug zip bundle at output_path."""
    output_path = Path(output_path)
    if output_path.suffix != ".strawwu-bug":
        output_path = output_path.with_suffix(".strawwu-bug")

    manifest = build_manifest(notes=notes, upload_consent=upload_consent)
    system = build_system_json()
    journal = _collect_journal()
    dmesg = _collect_dmesg()
    lsblk = _collect_lsblk()
    registry = _collect_registry_summary()

    if dry_run:
        return output_path

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="strawwu-bug-") as tmp:
        root = Path(tmp)
        (root / "manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        system_payload = dict(system)
        system_payload["lsblk"] = lsblk
        (root / "system.json").write_text(
            json.dumps(system_payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        (root / "journal.txt").write_text(journal + "\n", encoding="utf-8")
        (root / "dmesg.txt").write_text(dmesg + "\n", encoding="utf-8")
        (root / "user-notes.txt").write_text((notes or "").strip() + "\n", encoding="utf-8")

        logs_dir = root / "logs"
        logs_dir.mkdir()
        for name in LOG_NAMES:
            src = STRAWWU_LOG_DIR / name
            if src.is_file():
                content = redact_text(src.read_text(encoding="utf-8", errors="replace"))
                (logs_dir / name).write_text(content, encoding="utf-8")

        if registry is not None:
            (root / "registry.json").write_text(
                json.dumps(registry, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )

        with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(root).as_posix())

    return output_path


def validate_bundle(path: Path) -> list[str]:
    """Return list of validation errors (empty if OK)."""
    errors: list[str] = []
    required = {"manifest.json", "system.json", "journal.txt", "dmesg.txt", "user-notes.txt"}
    try:
        with zipfile.ZipFile(path) as zf:
            names = set(zf.namelist())
            missing = required - names
            if missing:
                errors.append(f"missing entries: {sorted(missing)}")
            manifest = json.loads(zf.read("manifest.json"))
            if manifest.get("format") != BUNDLE_FORMAT:
                errors.append("invalid manifest format")
            if manifest.get("consent", {}).get("auto_upload_default") is not False:
                errors.append("auto_upload_default must be false")
    except (zipfile.BadZipFile, KeyError, json.JSONDecodeError, OSError) as exc:
        errors.append(str(exc))
    return errors

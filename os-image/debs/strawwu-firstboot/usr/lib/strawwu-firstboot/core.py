"""First-boot orchestration, state integration, and structured logging."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MANIFEST_PATH = Path("/usr/share/strawwu/firstboot/firstboot-manifest.yaml")
LOCALE_DIR = Path("/usr/share/strawwu/locale")
LOG_PATH = Path("/var/log/strawwu/firstboot.log")
PREFS_PATH = Path("/var/lib/strawwu/setup/firstboot-prefs.json")
ERROR_CRASH = "SWU-FB-001"
ERROR_STATE = "SWU-FB-003"
PKG_VERSION = "0.4.1.23"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _parse_simple_yaml(text: str) -> dict[str, Any]:
    root: dict[str, Any] = {}
    current_list: list[Any] | None = None
    current_key: str | None = None

    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if re.match(r"^\s+- ", raw):
            if current_list is not None:
                current_list.append(raw.strip()[2:].strip())
            continue
        if ":" not in raw:
            continue
        key, _, rest = raw.partition(":")
        key = key.strip()
        value = rest.strip()
        if value:
            root[key] = value
            current_list = None
            current_key = key
        else:
            current_list = []
            root[key] = current_list
            current_key = key

    for nested_key in ("legal", "error_codes"):
        block: dict[str, str] = {}
        in_block = False
        for raw in text.splitlines():
            if raw.strip() == f"{nested_key}:":
                in_block = True
                continue
            if in_block:
                if not raw.startswith("  ") or ":" not in raw:
                    if raw.strip() and not raw.startswith(" "):
                        break
                    continue
                sub_key, _, sub_val = raw.strip().partition(":")
                block[sub_key.strip()] = sub_val.strip()
        if block:
            root[nested_key] = block

    return root


def manifest_path() -> Path:
    override = os.environ.get("STRAWWU_FIRSTBOOT_MANIFEST")
    if override:
        return Path(override)
    return MANIFEST_PATH


def log_path() -> Path:
    override = os.environ.get("STRAWWU_FIRSTBOOT_LOG")
    if override:
        return Path(override)
    return LOG_PATH


def prefs_path() -> Path:
    override = os.environ.get("STRAWWU_FIRSTBOOT_PREFS")
    if override:
        return Path(override)
    return PREFS_PATH


def log_event(level: str, message: str, **fields: Any) -> None:
    entry = {"ts": utc_now(), "level": level, "msg": message, **fields}
    line = json.dumps(entry, ensure_ascii=False)
    path = log_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        print(line, file=sys.stderr)


def load_manifest(path: Path | None = None) -> dict[str, Any]:
    target = path or manifest_path()
    if not target.exists():
        return {}
    return _parse_simple_yaml(target.read_text(encoding="utf-8"))


def step_ids(manifest: dict[str, Any] | None = None) -> list[str]:
    data = manifest or load_manifest()
    steps = data.get("steps", [])
    if not isinstance(steps, list):
        return []
    ordered: list[tuple[int, str]] = []
    for item in steps:
        if isinstance(item, dict) and "id" in item:
            order = int(item.get("order", 0))
            ordered.append((order, str(item["id"])))
        elif isinstance(item, str):
            ordered.append((len(ordered) + 1, item))
    ordered.sort(key=lambda pair: pair[0])
    return [step_id for _, step_id in ordered]


def initd_cmd(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["strawwu-initd", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def read_lifecycle_firstboot() -> str | None:
    proc = initd_cmd("get", "lifecycle.firstboot")
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def read_firstboot_required() -> bool:
    proc = initd_cmd("get", "flags.firstboot_required")
    if proc.returncode != 0:
        return True
    value = proc.stdout.strip().lower()
    return value in {"true", "1", "yes"}


def set_lifecycle(value: str, *, dry_run: bool = False) -> bool:
    log_event("info", "set lifecycle.firstboot", value=value, dry_run=dry_run)
    if dry_run:
        return True
    proc = initd_cmd("set", "lifecycle.firstboot", value)
    if proc.returncode != 0:
        log_event(
            "error",
            "initd set failed",
            code=ERROR_STATE,
            stderr=proc.stderr.strip(),
        )
        return False
    return True


def should_run(*, dry_run: bool = False) -> bool:
    if dry_run and os.environ.get("STRAWWU_FIRSTBOOT_FORCE") == "1":
        return True
    if not read_firstboot_required():
        log_event("info", "firstboot not required")
        return False
    phase = read_lifecycle_firstboot()
    if phase is None:
        log_event("error", "state unreadable", code=ERROR_STATE)
        return False
    if phase in {"done", "skipped"}:
        log_event("info", "firstboot already complete", phase=phase)
        return False
    return True


def load_prefs() -> dict[str, Any]:
    path = prefs_path()
    if not path.exists():
        return default_prefs()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return default_prefs()


def default_prefs() -> dict[str, Any]:
    manifest = load_manifest()
    return {
        "schema_version": "1.0",
        "locale": manifest.get("default_locale", "zh_TW.UTF-8"),
        "bug_upload_opt_in": False,
        "analytics_opt_in": False,
        "completed_steps": [],
        "updated_at": utc_now(),
    }


def save_prefs(prefs: dict[str, Any], *, dry_run: bool = False) -> None:
    prefs["updated_at"] = utc_now()
    path = prefs_path()
    log_event("info", "save prefs", path=str(path), dry_run=dry_run)
    if dry_run:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(prefs, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(path)


def apply_locale(locale: str, *, dry_run: bool = False) -> None:
    log_event("info", "apply locale", locale=locale, dry_run=dry_run)
    if dry_run:
        return
    if subprocess.run(["which", "localectl"], capture_output=True).returncode == 0:
        subprocess.run(["localectl", "set-locale", f"LANG={locale}"], check=False)
    config = Path.home() / ".config" / "locale.conf"
    try:
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(f"LANG={locale}\n", encoding="utf-8")
    except OSError as exc:
        log_event("warn", "locale.conf write failed", error=str(exc))


def complete_firstboot(prefs: dict[str, Any] | None = None, *, dry_run: bool = False) -> int:
    data = prefs or load_prefs()
    save_prefs(data, dry_run=dry_run)
    if not set_lifecycle("done", dry_run=dry_run):
        return 1
    log_event("info", "firstboot complete", steps=data.get("completed_steps", []))
    return 0


def run_dry_run() -> int:
    if not should_run(dry_run=True):
        if os.environ.get("STRAWWU_FIRSTBOOT_FORCE") != "1":
            print("firstboot: skip (not required or already done)")
            return 0
    steps = step_ids()
    prefs = default_prefs()
    prefs["completed_steps"] = steps
    log_event("info", "dry-run start", steps=steps)
    set_lifecycle("running", dry_run=True)
    apply_locale(str(prefs["locale"]), dry_run=True)
    rc = complete_firstboot(prefs, dry_run=True)
    print(f"firstboot dry-run: OK ({len(steps)} steps)")
    return rc


def run_autostart() -> int:
    if not should_run():
        return 0
    return run_wizard()


def run_wizard() -> int:
    log_event("info", "wizard start")
    if not set_lifecycle("running"):
        return 1
    try:
        from wizard_gtk4 import run_wizard_ui  # noqa: WPS433

        prefs = run_wizard_ui(load_prefs(), step_ids())
        if prefs is None:
            log_event("info", "wizard cancelled")
            return 1
        apply_locale(str(prefs.get("locale", "zh_TW.UTF-8")))
        return complete_firstboot(prefs)
    except ImportError as exc:
        log_event("error", "GTK4 unavailable", code=ERROR_CRASH, error=str(exc))
        print(f"ERROR [{ERROR_CRASH}]: GTK4/libadwaita not available: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # noqa: BLE001
        log_event("error", "wizard crash", code=ERROR_CRASH, error=str(exc))
        print(f"ERROR [{ERROR_CRASH}]: {exc}", file=sys.stderr)
        set_lifecycle("failed")
        return 1


def status_text() -> str:
    manifest = load_manifest()
    steps = step_ids(manifest)
    return (
        f"strawwu-firstboot {PKG_VERSION}\n"
        f"steps: {', '.join(steps)}\n"
        f"lifecycle.firstboot: {read_lifecycle_firstboot()}\n"
        f"firstboot_required: {read_firstboot_required()}\n"
        f"log: {log_path()}\n"
    )


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if manifest.get("schema") != "strawwu-firstboot-manifest/v1":
        errors.append("schema must be strawwu-firstboot-manifest/v1")
    ids = step_ids(manifest)
    if len(ids) != 6:
        errors.append(f"expected 6 steps, got {len(ids)}")
    expected = ["welcome", "language", "privacy", "flathub", "desktop", "finish"]
    if ids != expected:
        errors.append(f"step order mismatch: {ids!r}")
    codes = manifest.get("error_codes", {})
    if isinstance(codes, dict):
        if codes.get("crash") != ERROR_CRASH:
            errors.append("missing crash error code")
        if codes.get("state_mismatch") != ERROR_STATE:
            errors.append("missing state_mismatch error code")
    return errors

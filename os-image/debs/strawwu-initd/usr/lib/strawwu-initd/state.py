"""Read/write /var/lib/strawwu/setup/state.json with schema validation."""

from __future__ import annotations

import json
import os
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "1.0"
DEFAULT_STATE_PATH = Path("/var/lib/strawwu/setup/state.json")
DEFAULT_LOG_PATH = Path("/var/log/strawwu/initd.log")

LIFECYCLE_DEFAULTS = {
    "install": "pending",
    "target_setup": "pending",
    "boot_selfcheck": "pending",
    "firstboot": "pending",
}

LIFECYCLE_ENUMS = {
    "install": {"pending", "installing", "installed", "failed"},
    "target_setup": {"pending", "running", "done", "failed", "skipped"},
    "boot_selfcheck": {"pending", "running", "done", "failed"},
    "firstboot": {"pending", "running", "done", "skipped", "failed"},
}


def state_path() -> Path:
    override = os.environ.get("STRAWWU_SETUP_STATE")
    if override:
        return Path(override)
    return DEFAULT_STATE_PATH


def log_path() -> Path:
    override = os.environ.get("STRAWWU_INITD_LOG")
    if override:
        return Path(override)
    return DEFAULT_LOG_PATH


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def append_log(event: str, **fields: Any) -> None:
    entry = {"ts": utc_now(), "event": event, **fields}
    path = log_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def default_state() -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "updated_at": utc_now(),
        "lifecycle": dict(LIFECYCLE_DEFAULTS),
        "timestamps": {},
        "flags": {"firstboot_required": True},
        "meta": {"install_id": str(uuid.uuid4())},
    }


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def load_state(path: Path | None = None) -> dict[str, Any]:
    target = path or state_path()
    if not target.exists():
        raise FileNotFoundError(f"state file missing: {target}")
    with target.open(encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("state root must be an object")
    return data


def save_state(data: dict[str, Any], path: Path | None = None) -> None:
    target = path or state_path()
    data["updated_at"] = utc_now()
    ensure_parent(target)
    tmp = target.with_suffix(target.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    tmp.replace(target)
    append_log("state_saved", path=str(target))


def init_state(force: bool = False, path: Path | None = None) -> dict[str, Any]:
    target = path or state_path()
    if target.exists() and not force:
        return load_state(target)
    data = default_state()
    save_state(data, target)
    append_log("state_initialized", path=str(target), force=force)
    return data


def get_nested(data: dict[str, Any], dot_path: str) -> Any:
    node: Any = data
    for part in dot_path.split("."):
        if not isinstance(node, dict) or part not in node:
            raise KeyError(dot_path)
        node = node[part]
    return node


def set_nested(data: dict[str, Any], dot_path: str, value: Any) -> None:
    parts = dot_path.split(".")
    node: dict[str, Any] = data
    for part in parts[:-1]:
        if part not in node or not isinstance(node[part], dict):
            node[part] = {}
        node = node[part]
    leaf = parts[-1]
    if dot_path.startswith("lifecycle."):
        phase = parts[1]
        allowed = LIFECYCLE_ENUMS.get(phase)
        if allowed is None:
            raise ValueError(f"unknown lifecycle phase: {phase}")
        if value not in allowed:
            raise ValueError(f"invalid {phase} value: {value!r} (allowed: {sorted(allowed)})")
        node[leaf] = value
        ts_key = f"{phase}_at"
        if value in {"done", "installed", "skipped", "failed"}:
            timestamps = data.setdefault("timestamps", {})
            timestamps[ts_key] = utc_now()
        return
    node[leaf] = value


def validate_state(data: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    if data.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION!r}")

    lifecycle = data.get("lifecycle")
    if not isinstance(lifecycle, dict):
        errors.append("lifecycle must be an object")
        return errors

    for phase, allowed in LIFECYCLE_ENUMS.items():
        value = lifecycle.get(phase)
        if value not in allowed:
            errors.append(f"lifecycle.{phase} invalid: {value!r}")

    flags = data.get("flags")
    if not isinstance(flags, dict):
        errors.append("flags must be an object")
    elif "firstboot_required" not in flags:
        errors.append("flags.firstboot_required required")

    timestamps = data.get("timestamps", {})
    if timestamps is not None and not isinstance(timestamps, dict):
        errors.append("timestamps must be an object")

    meta = data.get("meta", {})
    if meta is not None and not isinstance(meta, dict):
        errors.append("meta must be an object")

    return errors


def repair_state(path: Path | None = None) -> dict[str, Any]:
    target = path or state_path()
    backup: Path | None = None

    if target.exists():
        try:
            data = load_state(target)
            errors = validate_state(data)
            if not errors:
                append_log("repair_ok", path=str(target))
                return data
        except (OSError, json.JSONDecodeError, ValueError):
            pass

        backup = target.with_suffix(target.suffix + f".bak.{datetime.now().strftime('%Y%m%d%H%M%S')}")
        shutil.copy2(target, backup)
        append_log("repair_backup", path=str(target), backup=str(backup))

    data = init_state(force=True, path=target)
    append_log("repair_reinitialized", path=str(target), backup=str(backup) if backup else None)
    return data


def migrate_state(path: Path | None = None, dry_run: bool = False) -> dict[str, Any]:
    target = path or state_path()
    if not target.exists():
        data = default_state()
        if not dry_run:
            save_state(data, target)
        append_log("migrate_created_default", path=str(target), dry_run=dry_run)
        return data

    data = load_state(target)
    version = data.get("schema_version")
    if version == SCHEMA_VERSION:
        append_log("migrate_noop", path=str(target), schema_version=version)
        return data

    raise ValueError(f"unsupported schema_version for migration: {version!r}")

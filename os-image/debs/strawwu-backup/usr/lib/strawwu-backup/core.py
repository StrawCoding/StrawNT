"""StrawWU system backup — rsync / Btrfs / Timeshift PoC."""

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

MANIFEST_PATH = Path("/usr/share/strawwu/backup/backup-manifest.yaml")
FIXTURE_PATH = Path("/usr/share/strawwu/backup/fixture-catalog.json")
DEFAULT_BACKUP_ROOT = Path("/var/lib/strawwu/backups")
DEFAULT_SYSTEM_DIR = "system"
UPGRADE_PREFIX = "pre-upgrade-"
SNAPSHOT_SCHEMA = "strawwu-backup-snapshot/v1"
MIN_FREE_MB = 1024
LOG_PATH = Path("/var/log/strawwu/backup.log")
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


def backup_root() -> Path:
    override = os.environ.get("STRAWWU_BACKUP_ROOT") or os.environ.get(
        "STRAWWU_UPGRADE_BACKUP_ROOT"
    )
    if override:
        return Path(override)
    return DEFAULT_BACKUP_ROOT


def system_root() -> Path:
    return backup_root() / DEFAULT_SYSTEM_DIR


def fixture_path() -> Path:
    override = os.environ.get("STRAWWU_BACKUP_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "backup" / "fixture-catalog.json"
    if dev.is_file():
        return dev
    return FIXTURE_PATH


def use_fixture_mode() -> bool:
    return os.environ.get("STRAWWU_BACKUP_FIXTURE") == "1"


def read_fixture() -> dict[str, Any]:
    path = fixture_path()
    if not path.is_file():
        return {
            "schema": "strawwu-backup-fixture/v1",
            "mock": True,
            "disk_free_mb": 4096,
            "backends": {"rsync": True, "btrfs": False, "timeshift": False},
            "snapshots": [],
        }
    return json.loads(path.read_text(encoding="utf-8"))


def run_cmd(args: list[str], *, timeout: int = 600) -> subprocess.CompletedProcess[str]:
    log_event("info", "exec", cmd=args)
    return subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)


def disk_free_mb(path: Path) -> int:
    if use_fixture_mode():
        return int(read_fixture().get("disk_free_mb", 4096))
    try:
        usage = shutil.disk_usage(path)
        return usage.free // (1024 * 1024)
    except OSError:
        return 0


def root_fstype() -> str | None:
    if use_fixture_mode():
        return "ext4" if not read_fixture().get("backends", {}).get("btrfs") else "btrfs"
    proc = run_cmd(["findmnt", "-n", "-o", "FSTYPE", "/"], timeout=10)
    if proc.returncode == 0 and proc.stdout.strip():
        return proc.stdout.strip()
    return None


def timeshift_cli() -> Path | None:
    override = os.environ.get("STRAWWU_BACKUP_TIMESHIFT_CLI")
    if override:
        path = Path(override)
        return path if path.is_file() else None
    for candidate in (Path("/usr/bin/timeshift"), Path("/bin/timeshift")):
        if candidate.is_file():
            return candidate
    return None


def detect_backends() -> dict[str, Any]:
    if use_fixture_mode():
        fixture = read_fixture()
        backends = fixture.get("backends", {})
        return {
            "rsync": bool(backends.get("rsync", True)),
            "btrfs": bool(backends.get("btrfs", False)),
            "timeshift": bool(backends.get("timeshift", False)),
            "preferred": fixture.get("status", {}).get("preferred_backend", "rsync"),
        }

    fstype = root_fstype()
    ts = timeshift_cli()
    preferred = "rsync"
    if ts is not None:
        preferred = "timeshift"
    elif fstype == "btrfs":
        preferred = "btrfs"
    return {
        "rsync": shutil.which("rsync") is not None,
        "btrfs": fstype == "btrfs" and shutil.which("btrfs") is not None,
        "timeshift": ts is not None,
        "preferred": preferred,
    }


def safe_label(label: str | None) -> str:
    if not label:
        return "manual"
    cleaned = re.sub(r"[^0-9A-Za-z._-]", "-", label.strip())
    return cleaned[:48] or "manual"


def snapshot_name(label: str | None = None) -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"system-{stamp}-{safe_label(label)}"


def snapshot_dir(name: str) -> Path:
    return system_root() / name


def read_upgrade_manifest(entry: Path) -> dict[str, Any]:
    manifest_file = entry / "manifest.json"
    if manifest_file.is_file():
        return json.loads(manifest_file.read_text(encoding="utf-8"))
    return {}


def list_upgrade_snapshots() -> list[dict[str, Any]]:
    if use_fixture_mode():
        return [
            snap
            for snap in read_fixture().get("snapshots", [])
            if snap.get("kind") == "upgrade"
        ]

    root = backup_root()
    if not root.is_dir():
        return []
    results: list[dict[str, Any]] = []
    for entry in sorted(root.iterdir()):
        if not entry.is_dir() or not entry.name.startswith(UPGRADE_PREFIX):
            continue
        manifest = read_upgrade_manifest(entry)
        results.append(
            {
                "name": entry.name,
                "kind": "upgrade",
                "backend": "strawwu-upgrade",
                "path": str(entry),
                "created_at": manifest.get("created_at"),
                "from_version": manifest.get("from_version"),
                "target_version": manifest.get("target_version"),
                "restore_cli": "strawwu-upgrade --rollback",
            }
        )
    return results


def list_system_snapshots() -> list[dict[str, Any]]:
    root = system_root()
    if not root.is_dir():
        return []
    results: list[dict[str, Any]] = []
    for entry in sorted(root.iterdir()):
        if not entry.is_dir() or not entry.name.startswith("system-"):
            continue
        manifest_file = entry / "manifest.json"
        manifest = (
            json.loads(manifest_file.read_text(encoding="utf-8"))
            if manifest_file.is_file()
            else {}
        )
        results.append(
            {
                "name": entry.name,
                "kind": "system",
                "backend": manifest.get("backend", "rsync"),
                "path": str(entry),
                "created_at": manifest.get("created_at"),
                "label": manifest.get("label"),
            }
        )
    return results


def list_snapshots() -> list[dict[str, Any]]:
    if use_fixture_mode():
        fixture_snaps = list_upgrade_snapshots()
        names = {s.get("name") for s in fixture_snaps}
        for snap in list_system_snapshots():
            if snap.get("name") not in names:
                fixture_snaps.append(snap)
                names.add(snap.get("name"))
        for snap in read_fixture().get("snapshots", []):
            if snap.get("kind") == "system" and snap.get("name") not in names:
                fixture_snaps.append(snap)
                names.add(snap.get("name"))
        return fixture_snaps
    return list_system_snapshots() + list_upgrade_snapshots()


def rsync_paths() -> list[Path]:
    manifest = MANIFEST_PATH if MANIFEST_PATH.is_file() else (
        _PKG_USR / "share" / "strawwu" / "backup" / "backup-manifest.yaml"
    )
    paths: list[Path] = []
    if manifest.is_file():
        for line in manifest.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("- /"):
                paths.append(Path(line[2:].strip()))
    if not paths:
        paths = [Path("/etc/strawwu"), Path("/var/lib/strawwu/setup")]
    return paths


def write_snapshot_manifest(
    snap_dir: Path,
    *,
    label: str,
    backend: str,
    paths: list[str],
) -> dict[str, Any]:
    manifest = {
        "schema": SNAPSHOT_SCHEMA,
        "created_at": utc_now(),
        "label": label,
        "backend": backend,
        "paths": paths,
        "restore_hint": "strawwu-backup restore --dry-run <name>",
    }
    snap_dir.mkdir(parents=True, exist_ok=True)
    (snap_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return manifest


def rsync_snapshot(snap_dir: Path, *, label: str) -> dict[str, Any]:
    copied: list[str] = []
    for src in rsync_paths():
        if use_fixture_mode():
            if src.name:
                copied.append(str(src))
            continue
        if not src.exists():
            log_event("warn", "rsync_skip_missing", path=str(src))
            continue
        dst = snap_dir / "files" / src.relative_to("/")
        dst.parent.mkdir(parents=True, exist_ok=True)
        proc = run_cmd(
            [
                "rsync",
                "-a",
                "--delete",
                f"{src}/",
                f"{dst}/",
            ]
        )
        if proc.returncode != 0:
            raise RuntimeError(f"rsync failed for {src}: {proc.stderr.strip()}")
        copied.append(str(src))
    manifest = write_snapshot_manifest(snap_dir, label=label, backend="rsync", paths=copied)
    log_event("info", "rsync_snapshot_created", snapshot=snap_dir.name, paths=len(copied))
    return manifest


def btrfs_snapshot(snap_dir: Path, *, label: str) -> dict[str, Any]:
    if use_fixture_mode():
        manifest = write_snapshot_manifest(
            snap_dir, label=label, backend="btrfs", paths=["/"]
        )
        return manifest
    proc = run_cmd(["btrfs", "subvolume", "snapshot", "/", str(snap_dir)])
    if proc.returncode != 0:
        raise RuntimeError(f"btrfs snapshot failed: {proc.stderr.strip()}")
    manifest = write_snapshot_manifest(snap_dir, label=label, backend="btrfs", paths=["/"])
    log_event("info", "btrfs_snapshot_created", snapshot=snap_dir.name)
    return manifest


def timeshift_list() -> list[dict[str, Any]]:
    cli = timeshift_cli()
    if cli is None:
        return []
    if use_fixture_mode():
        return list(read_fixture().get("timeshift", {}).get("snapshots", []))
    proc = run_cmd([str(cli), "--list", "--scripted"], timeout=120)
    if proc.returncode != 0:
        log_event("warn", "timeshift_list_failed", stderr=proc.stderr.strip())
        return []
    results: list[dict[str, Any]] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("UUID"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 3:
            results.append(
                {
                    "id": parts[0],
                    "tags": parts[1] if len(parts) > 1 else "",
                    "description": parts[2] if len(parts) > 2 else "",
                }
            )
    return results


def create_snapshot(
    *,
    label: str | None = None,
    backend: str | None = None,
) -> dict[str, Any]:
    backends = detect_backends()
    chosen = backend or backends.get("preferred", "rsync")
    if chosen not in backends or not backends[chosen]:
        raise RuntimeError(f"backend unavailable: {chosen}")

    name = snapshot_name(label)
    snap_dir = snapshot_dir(name)
    if snap_dir.exists() and any(snap_dir.iterdir()):
        raise FileExistsError(f"snapshot already exists: {snap_dir}")

    if chosen == "timeshift":
        cli = timeshift_cli()
        if cli is None:
            raise RuntimeError("timeshift not installed")
        if use_fixture_mode():
            manifest = write_snapshot_manifest(
                snap_dir, label=safe_label(label), backend="timeshift", paths=["/"]
            )
            return {
                "snapshot": name,
                "path": str(snap_dir),
                "backend": "timeshift",
                "manifest": manifest,
                "timeshift": {"mode": "fixture"},
            }
        proc = run_cmd(
            [
                str(cli),
                "--create",
                "--comments",
                safe_label(label),
                "--scripted",
            ],
            timeout=1800,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"timeshift create failed: {proc.stderr.strip()}")
        manifest = write_snapshot_manifest(
            snap_dir, label=safe_label(label), backend="timeshift", paths=["/"]
        )
        return {
            "snapshot": name,
            "path": str(snap_dir),
            "backend": "timeshift",
            "manifest": manifest,
            "timeshift": {"created": True},
        }

    if chosen == "btrfs":
        manifest = btrfs_snapshot(snap_dir, label=safe_label(label))
        return {
            "snapshot": name,
            "path": str(snap_dir),
            "backend": "btrfs",
            "manifest": manifest,
        }

    manifest = rsync_snapshot(snap_dir, label=safe_label(label))
    return {
        "snapshot": name,
        "path": str(snap_dir),
        "backend": "rsync",
        "manifest": manifest,
    }


def find_snapshot(name: str) -> dict[str, Any] | None:
    for snap in list_snapshots():
        if snap.get("name") == name:
            return snap
    direct = snapshot_dir(name)
    if direct.is_dir():
        manifest_file = direct / "manifest.json"
        manifest = (
            json.loads(manifest_file.read_text(encoding="utf-8"))
            if manifest_file.is_file()
            else {}
        )
        return {
            "name": name,
            "kind": "system",
            "backend": manifest.get("backend", "rsync"),
            "path": str(direct),
            "created_at": manifest.get("created_at"),
            "label": manifest.get("label"),
        }
    return None


def restore_snapshot(name: str, *, dry_run: bool = True) -> dict[str, Any]:
    snap = find_snapshot(name)
    if snap is None:
        raise FileNotFoundError(f"snapshot not found: {name}")

    kind = snap.get("kind", "system")
    actions: list[str] = []

    if kind == "upgrade":
        actions.append(f"strawwu-upgrade --rollback {name}")
        if not dry_run:
            if shutil.which("strawwu-upgrade"):
                proc = run_cmd(["strawwu-upgrade", "--rollback", name])
                if proc.returncode != 0:
                    raise RuntimeError(proc.stderr.strip() or "rollback failed")
            else:
                raise RuntimeError("strawwu-upgrade not installed")
        return {"snapshot": name, "kind": kind, "dry_run": dry_run, "actions": actions}

    snap_path = Path(snap.get("path", snapshot_dir(name)))
    manifest_file = snap_path / "manifest.json"
    manifest = (
        json.loads(manifest_file.read_text(encoding="utf-8"))
        if manifest_file.is_file()
        else snap
    )
    backend = manifest.get("backend", snap.get("backend", "rsync"))

    if backend == "timeshift":
        actions.append(f"timeshift --restore --snapshot '{name}' --scripted")
        if not dry_run:
            cli = timeshift_cli()
            if cli is None:
                raise RuntimeError("timeshift not installed")
            proc = run_cmd([str(cli), "--restore", "--snapshot", name, "--scripted"], timeout=1800)
            if proc.returncode != 0:
                raise RuntimeError(proc.stderr.strip() or "timeshift restore failed")
    else:
        for src in manifest.get("paths", []):
            src_path = Path(src)
            backup_files = snap_path / "files" / src_path.relative_to("/")
            actions.append(f"rsync -a {backup_files}/ -> {src_path}/")
            if not dry_run and backup_files.is_dir():
                src_path.parent.mkdir(parents=True, exist_ok=True)
                proc = run_cmd(["rsync", "-a", f"{backup_files}/", f"{src_path}/"])
                if proc.returncode != 0:
                    raise RuntimeError(f"restore failed for {src}: {proc.stderr.strip()}")

    log_event("info", "restore_plan", snapshot=name, dry_run=dry_run, backend=backend)
    return {
        "snapshot": name,
        "kind": kind,
        "backend": backend,
        "dry_run": dry_run,
        "actions": actions,
    }


def backup_status() -> dict[str, Any]:
    backends = detect_backends()
    snaps = list_snapshots()
    system_count = sum(1 for s in snaps if s.get("kind") == "system")
    upgrade_count = sum(1 for s in snaps if s.get("kind") == "upgrade")
    return {
        "schema": "strawwu-backup-status/v1",
        "backup_root": str(backup_root()),
        "system_root": str(system_root()),
        "backends": backends,
        "timeshift_snapshots": timeshift_list(),
        "snapshot_count": len(snaps),
        "system_count": system_count,
        "upgrade_count": upgrade_count,
        "upgrade_hook": "strawwu-upgrade snapshot",
        "hub_panel": "backup",
        "fixture": use_fixture_mode(),
    }


def run_preflight() -> dict[str, Any]:
    issues: list[str] = []
    root = backup_root()
    free_mb = disk_free_mb(root)
    if free_mb < MIN_FREE_MB:
        issues.append(f"insufficient disk space: {free_mb}MB < {MIN_FREE_MB}MB required")

    backends = detect_backends()
    if not backends.get("rsync") and not backends.get("btrfs") and not backends.get("timeshift"):
        issues.append("no backup backend available (rsync/btrfs/timeshift)")

    manifest = MANIFEST_PATH if MANIFEST_PATH.is_file() else (
        _PKG_USR / "share" / "strawwu" / "backup" / "backup-manifest.yaml"
    )
    if not manifest.is_file() and not use_fixture_mode():
        issues.append("missing backup-manifest.yaml")

    if not use_fixture_mode():
        try:
            root.mkdir(parents=True, exist_ok=True)
            probe = root / ".preflight-write-test"
            probe.write_text("ok\n", encoding="utf-8")
            probe.unlink()
        except OSError as exc:
            issues.append(f"backup root not writable: {exc}")

    return {
        "ok": len(issues) == 0,
        "issues": issues,
        "disk_free_mb": free_mb,
        "backends": backends,
        "fixture": use_fixture_mode(),
    }


def cmd_version() -> int:
    print("strawwu-backup 0.7.0.10-target (PoC)")
    return 0

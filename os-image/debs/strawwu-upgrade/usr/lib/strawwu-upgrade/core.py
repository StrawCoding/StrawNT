"""StrawWU upgrade orchestration — preflight, snapshot, rollback."""

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

MANIFEST_PATH = Path("/usr/share/strawwu/upgrade/upgrade-manifest.yaml")
FIXTURE_PATH = Path("/usr/share/strawwu/upgrade/fixture-catalog.json")
DEFAULT_BACKUP_ROOT = Path("/var/lib/strawwu/backups")
DEFAULT_STATE_PATH = Path("/var/lib/strawwu/setup/state.json")
DEFAULT_BOOT_DIR = Path("/boot")
LOG_PATH = Path("/var/log/strawwu/upgrade.log")
SNAPSHOT_SCHEMA = "strawwu-upgrade-snapshot/v1"
MIN_FREE_MB = 512
KERNEL_KEEP_COUNT = 2
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
    override = os.environ.get("STRAWWU_UPGRADE_BACKUP_ROOT")
    if override:
        return Path(override)
    return DEFAULT_BACKUP_ROOT


def state_path() -> Path:
    override = os.environ.get("STRAWWU_SETUP_STATE")
    if override:
        return Path(override)
    return DEFAULT_STATE_PATH


def boot_dir() -> Path:
    override = os.environ.get("STRAWWU_UPGRADE_BOOT_DIR")
    if override:
        return Path(override)
    return DEFAULT_BOOT_DIR


def fixture_path() -> Path:
    override = os.environ.get("STRAWWU_UPGRADE_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "upgrade" / "fixture-catalog.json"
    if dev.is_file():
        return dev
    return FIXTURE_PATH


def use_fixture_mode() -> bool:
    return os.environ.get("STRAWWU_UPGRADE_FIXTURE") == "1"


def read_fixture() -> dict[str, Any]:
    path = fixture_path()
    if not path.is_file():
        return {"schema": "strawwu-upgrade-fixture/v1", "mock": True}
    return json.loads(path.read_text(encoding="utf-8"))


def read_version() -> str:
    override = os.environ.get("STRAWWU_VERSION")
    if override:
        return override.strip()
    for candidate in (
        Path("/etc/os-release"),
        Path("/usr/share/strawwu/VERSION"),
    ):
        if not candidate.is_file():
            continue
        for line in candidate.read_text(encoding="utf-8").splitlines():
            if line.startswith("VERSION="):
                return line.split("=", 1)[1].strip().strip('"')
    return "0.0.0.0"


def snapshot_name(target_version: str | None = None) -> str:
    ver = target_version or read_version()
    safe = re.sub(r"[^0-9A-Za-z._-]", "_", ver)
    return f"pre-upgrade-{safe}"


def snapshot_dir(name: str | None = None) -> Path:
    return backup_root() / (name or snapshot_name())


def run_cmd(args: list[str], *, timeout: int = 300) -> subprocess.CompletedProcess[str]:
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


def load_state_data() -> dict[str, Any]:
    path = state_path()
    if use_fixture_mode():
        fixture = read_fixture()
        if fixture.get("state"):
            return dict(fixture["state"])
    if not path.is_file():
        raise FileNotFoundError(f"state missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def validate_state_data(data: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if data.get("schema_version") != "1.0":
        errors.append(f"unsupported schema_version: {data.get('schema_version')!r}")
    lifecycle = data.get("lifecycle")
    if not isinstance(lifecycle, dict):
        errors.append("lifecycle must be an object")
    return errors


def list_strawwu_packages() -> dict[str, str]:
    if use_fixture_mode():
        pkgs = read_fixture().get("packages", {})
        return {str(k): str(v) for k, v in pkgs.items()}

    proc = run_cmd(["dpkg-query", "-W", "-f=${Package}\t${Version}\n", "strawwu-*"])
    packages: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        if "\t" not in line:
            continue
        pkg, ver = line.split("\t", 1)
        packages[pkg] = ver
    return packages


def boot_artifacts() -> dict[str, str]:
    if use_fixture_mode():
        boot = read_fixture().get("boot", {})
        return {str(k): str(v) for k, v in boot.items()}

    root = boot_dir()
    artifacts: dict[str, str] = {}
    vmlinuz = sorted(root.glob("vmlinuz-*"), key=lambda p: p.stat().st_mtime, reverse=True)
    initrd = sorted(root.glob("initrd.img-*"), key=lambda p: p.stat().st_mtime, reverse=True)
    if vmlinuz:
        artifacts["vmlinuz"] = vmlinuz[0].name
    if initrd:
        artifacts["initrd"] = initrd[0].name
    old_initrd = root / "initrd.img.old"
    if old_initrd.is_symlink() or old_initrd.is_file():
        artifacts["initrd_old"] = old_initrd.name
    return artifacts


def kernel_entries() -> list[str]:
    root = boot_dir()
    return sorted(p.name for p in root.glob("vmlinuz-*"))


def write_snapshot_manifest(
    snap_dir: Path,
    *,
    from_version: str,
    target_version: str | None,
) -> dict[str, Any]:
    manifest = {
        "schema": SNAPSHOT_SCHEMA,
        "created_at": utc_now(),
        "from_version": from_version,
        "target_version": target_version,
        "state_path": str(state_path()),
        "packages": list_strawwu_packages(),
        "boot": boot_artifacts(),
        "kernel_entries": kernel_entries(),
    }
    snap_dir.mkdir(parents=True, exist_ok=True)
    (snap_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return manifest


def copy_state_into_snapshot(snap_dir: Path) -> None:
    src = state_path()
    if not src.is_file():
        if use_fixture_mode():
            data = load_state_data()
            (snap_dir / "state.json").write_text(
                json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            return
        raise FileNotFoundError(f"state missing: {src}")
    shutil.copy2(src, snap_dir / "state.json")


def create_snapshot(target_version: str | None = None) -> dict[str, Any]:
    from_ver = read_version()
    name = snapshot_name(target_version or from_ver)
    snap_dir = snapshot_dir(name)
    if snap_dir.exists() and any(snap_dir.iterdir()):
        raise FileExistsError(f"snapshot already exists: {snap_dir}")

    snap_dir.mkdir(parents=True, exist_ok=True)
    copy_state_into_snapshot(snap_dir)
    manifest = write_snapshot_manifest(snap_dir, from_version=from_ver, target_version=target_version)
    log_event("info", "snapshot_created", snapshot=name, from_version=from_ver)
    return {"snapshot": name, "path": str(snap_dir), "manifest": manifest}


def list_snapshots() -> list[dict[str, Any]]:
    root = backup_root()
    if not root.is_dir():
        return []
    results: list[dict[str, Any]] = []
    for entry in sorted(root.iterdir()):
        if not entry.is_dir() or not entry.name.startswith("pre-upgrade-"):
            continue
        manifest_file = entry / "manifest.json"
        if manifest_file.is_file():
            manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        else:
            manifest = {}
        results.append(
            {
                "name": entry.name,
                "path": str(entry),
                "created_at": manifest.get("created_at"),
                "from_version": manifest.get("from_version"),
            }
        )
    return results


def latest_snapshot_name() -> str | None:
    snaps = list_snapshots()
    return snaps[-1]["name"] if snaps else None


def restore_state_from_snapshot(snap_dir: Path) -> None:
    src = snap_dir / "state.json"
    if not src.is_file():
        raise FileNotFoundError(f"snapshot missing state.json: {snap_dir}")
    dst = state_path()
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.is_file():
        backup = dst.with_suffix(dst.suffix + f".rollback.{utc_now().replace(':', '')}")
        shutil.copy2(dst, backup)
    shutil.copy2(src, dst)


def restore_boot_symlinks(manifest: dict[str, Any], *, dry_run: bool = False) -> list[str]:
    actions: list[str] = []
    boot = manifest.get("boot", {})
    root = boot_dir()
    initrd_name = boot.get("initrd")
    if initrd_name:
        target = root / initrd_name
        old_link = root / "initrd.img.old"
        if target.is_file():
            actions.append(f"restore symlink {old_link} -> {target.name}")
            if not dry_run:
                if old_link.is_symlink() or old_link.is_file():
                    old_link.unlink()
                old_link.symlink_to(target.name)
    return actions


def invoke_target_setup_repair(*, dry_run: bool = False) -> int:
    if dry_run or use_fixture_mode():
        log_event("info", "repair_skipped", reason="dry_run_or_fixture")
        return 0
    if not shutil.which("strawwu-target-setup"):
        log_event("warn", "repair_skipped", reason="strawwu-target-setup missing")
        return 0
    proc = run_cmd(["strawwu-target-setup", "--repair-only"])
    if proc.returncode != 0:
        log_event("error", "repair_failed", stderr=proc.stderr.strip())
    return proc.returncode


def rollback(snapshot: str | None = None, *, dry_run: bool = False) -> dict[str, Any]:
    name = snapshot or latest_snapshot_name()
    if not name:
        raise FileNotFoundError("no pre-upgrade snapshot found")

    snap_dir = snapshot_dir(name)
    manifest_file = snap_dir / "manifest.json"
    if not manifest_file.is_file():
        raise FileNotFoundError(f"snapshot manifest missing: {manifest_file}")

    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    if manifest.get("schema") != SNAPSHOT_SCHEMA:
        raise ValueError(f"unsupported snapshot schema: {manifest.get('schema')!r}")

    actions = [f"restore state from {snap_dir / 'state.json'}"]
    if not dry_run:
        restore_state_from_snapshot(snap_dir)
    actions.extend(restore_boot_symlinks(manifest, dry_run=dry_run))
    repair_rc = invoke_target_setup_repair(dry_run=dry_run)
    actions.append("strawwu-target-setup --repair-only")

    log_event("info", "rollback_complete", snapshot=name, dry_run=dry_run)
    return {
        "snapshot": name,
        "from_version": manifest.get("from_version"),
        "actions": actions,
        "repair_rc": repair_rc,
    }


def run_preflight(*, target_version: str | None = None) -> dict[str, Any]:
    issues: list[str] = []
    free_mb = disk_free_mb(backup_root())
    if free_mb < MIN_FREE_MB:
        issues.append(f"insufficient disk space: {free_mb}MB < {MIN_FREE_MB}MB required")

    try:
        state = load_state_data()
        issues.extend(validate_state_data(state))
    except (OSError, json.JSONDecodeError, FileNotFoundError) as exc:
        issues.append(f"state invalid: {exc}")

    kernels = kernel_entries()
    if not use_fixture_mode() and len(kernels) < 1:
        issues.append("no kernel images found under /boot")

    result = {
        "ok": not issues,
        "issues": issues,
        "disk_free_mb": free_mb,
        "from_version": read_version(),
        "target_version": target_version,
        "kernel_count": len(kernels),
        "packages": list_strawwu_packages(),
    }
    log_event("info", "preflight", ok=result["ok"], issues=issues)
    return result


def run_upgrade(*, target_version: str | None = None, dry_run: bool = False) -> dict[str, Any]:
    pre = run_preflight(target_version=target_version)
    if not pre["ok"]:
        raise RuntimeError("; ".join(pre["issues"]))

    snap = create_snapshot(target_version)
    actions = [f"snapshot {snap['snapshot']}"]

    if dry_run or use_fixture_mode():
        actions.append("apt full-upgrade (skipped: dry-run/fixture)")
        return {"preflight": pre, "snapshot": snap, "actions": actions, "dry_run": True}

    # Real upgrade path — orchestrate apt meta upgrade.
    if shutil.which("apt-get"):
        proc = run_cmd(
            [
                "apt-get",
                "update",
                "-qq",
            ]
        )
        if proc.returncode != 0:
            raise RuntimeError(f"apt-get update failed: {proc.stderr.strip()}")
        proc = run_cmd(
            [
                "apt-get",
                "dist-upgrade",
                "-y",
                "-o",
                "Dpkg::Options::=--force-confdef",
                "-o",
                "Dpkg::Options::=--force-confold",
            ],
            timeout=3600,
        )
        actions.append("apt-get dist-upgrade")
        if proc.returncode != 0:
            rollback(snap["snapshot"])
            raise RuntimeError(f"apt dist-upgrade failed; rolled back: {proc.stderr.strip()}")

    return {"preflight": pre, "snapshot": snap, "actions": actions, "dry_run": False}


def cmd_version() -> int:
    ver = os.environ.get("STRAWWU_PKG_VERSION", "0.7.0.0")
    print(f"strawwu-upgrade {ver} (snapshot schema {SNAPSHOT_SCHEMA})")
    return 0

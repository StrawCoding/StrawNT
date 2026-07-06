"""Desktop remove orchestration — registry CLI + favorites sync."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from desktop_parse import display_name, ensure_desktop_action, parse_app_id, resolve_real_desktop
from favorites import add_to_favorites, favorites_available, remove_from_favorites, sync_favorites_from_registry
from i18n import format_message

DEFAULT_REGISTRY = Path("/var/lib/strawwu/app-registry.json")
DEFAULT_REGISTRY_CLI = Path("/usr/bin/strawwu-app-registry")


def registry_path() -> Path:
    override = os.environ.get("STRAWWU_APP_REGISTRY")
    if override:
        return Path(override)
    return DEFAULT_REGISTRY


def registry_cli() -> Path:
    dev = os.environ.get("STRAWWU_APP_REGISTRY_CLI")
    if dev:
        return Path(dev)
    repo_dev = Path(__file__).resolve().parents[4] / "components/target/debug/strawwu-app-registry"
    if repo_dev.exists():
        return repo_dev
    return DEFAULT_REGISTRY_CLI


def normalize_remove_payload(data: dict) -> dict:
    preview = data.get("preview")
    if isinstance(preview, dict):
        return preview
    return data


def remove_via_registry(desktop_path: Path, dry_run: bool = False) -> dict:
    cli = registry_cli()
    if not cli.exists():
        raise RuntimeError(f"missing registry CLI: {cli}")

    env = os.environ.copy()
    env.setdefault("STRAWWU_APP_REGISTRY", str(registry_path()))

    args = [str(cli), "remove-by-desktop", str(desktop_path), "--deep", "--json"]
    if dry_run:
        args.insert(-1, "--dry-run")

    result = subprocess.run(args, check=False, capture_output=True, text=True, env=env)
    if result.returncode == 2:
        name = display_name(desktop_path)
        raise PermissionError(format_message("protected_error", name=name))

    if result.returncode != 0:
        if "not found" in (result.stderr + result.stdout).lower():
            raise LookupError(format_message("not_registered"))
        app_id = parse_app_id(desktop_path)
        if not app_id:
            raise LookupError(format_message("not_registered"))
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "remove failed")

    preview = normalize_remove_payload(json.loads(result.stdout))
    return preview


def remove_desktop(desktop_path: Path, dry_run: bool = False, sync_favorites: bool = True) -> dict:
    desktop_path = resolve_real_desktop(desktop_path)
    preview = remove_via_registry(desktop_path, dry_run=dry_run)

    fav_removed = False
    if sync_favorites and not dry_run and favorites_available():
        fav_removed = remove_from_favorites(desktop_path)

    return {
        "preview": preview,
        "favorites_removed": fav_removed,
        "desktop": str(desktop_path),
    }


def register_desktop(
    desktop_path: Path,
    app_id: str,
    name: str,
    kind: str = "native",
    source: str = "manual",
    protected: bool = False,
    pin_favorite: bool = True,
) -> dict:
    desktop_path = resolve_real_desktop(desktop_path)
    ensure_desktop_action(desktop_path, app_id, protected=protected)

    cli = registry_cli()
    env = os.environ.copy()
    env.setdefault("STRAWWU_APP_REGISTRY", str(registry_path()))

    args = [
        str(cli),
        "register",
        "--id",
        app_id,
        "--name",
        name,
        "--kind",
        kind,
        "--source",
        source,
        "--desktop-entry",
        str(desktop_path),
    ]
    if protected:
        args.append("--protected")

    result = subprocess.run(args, check=False, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "register failed")

    fav_added = False
    if pin_favorite and favorites_available():
        fav_added = add_to_favorites(desktop_path)

    return {
        "app_id": app_id,
        "desktop": str(desktop_path),
        "favorites_added": fav_added,
    }


def sync_all() -> dict:
    return sync_favorites_from_registry(registry_path())


def main(argv: list[str] | None = None) -> int:
    args = list(argv or sys.argv[1:])
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    if not args or args[0] in ("-h", "--help"):
        print(
            "Usage: strawwu-desktop-remove --desktop <path> [--dry-run]\n"
            "       strawwu-desktop-remove sync-favorites\n"
            "       strawwu-desktop-remove inject-action --desktop <path> --id <app-id>"
        )
        return 0

    if args[0] == "sync-favorites":
        stats = sync_all()
        print(json.dumps(stats, ensure_ascii=False))
        return 0

    if args[0] == "inject-action":
        try:
            desk_idx = args.index("--desktop")
            id_idx = args.index("--id")
        except ValueError:
            print("inject-action requires --desktop and --id", file=sys.stderr)
            return 1
        desktop = Path(args[desk_idx + 1])
        app_id = args[id_idx + 1]
        changed = ensure_desktop_action(desktop, app_id)
        print(json.dumps({"desktop": str(desktop), "modified": changed}))
        return 0

    desktop_arg = None
    if "--desktop" in args:
        idx = args.index("--desktop")
        desktop_arg = args[idx + 1]
    elif args[0] == "--desktop" and len(args) > 1:
        desktop_arg = args[1]
    elif args[0].endswith(".desktop"):
        desktop_arg = args[0]

    if not desktop_arg:
        print("missing --desktop <path>", file=sys.stderr)
        return 1

    try:
        result = remove_desktop(Path(desktop_arg), dry_run=dry_run)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except PermissionError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except LookupError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

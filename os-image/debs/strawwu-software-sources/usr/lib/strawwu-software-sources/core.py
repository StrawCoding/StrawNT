"""StrawWU software sources manager — APT/Flatpak source listing and toggling."""

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

MANIFEST_PATH = Path("/usr/share/strawwu/software-sources/software-sources-manifest.yaml")
FIXTURE_PATH = Path("/usr/share/strawwu/software-sources/fixture-catalog.json")
LOG_PATH = Path("/var/log/strawwu/software-sources.log")
SOURCES_DIR = Path("/etc/apt/sources.list.d")
POLKIT_ACTION = "xyz.wastebase.strawwu.software-sources.toggle"
UPDATE_NOTIFIER = "strawwu-update-notifier"
PKG_VERSION = "0.6.3.9"
ERROR_CODE = "SWU-SRC-001"
_PKG_USR = Path(__file__).resolve().parent.parent.parent

READONLY_IDS = frozenset({"flathub", "ubuntu-security"})
STRAWWU_IDS = frozenset({"strawwu-official"})


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
    override = os.environ.get("STRAWWU_SOFTWARE_SOURCES_FIXTURE_PATH")
    if override:
        return Path(override)
    dev = _PKG_USR / "share" / "strawwu" / "software-sources" / "fixture-catalog.json"
    if dev.is_file():
        return dev
    return FIXTURE_PATH


def use_fixture_mode() -> bool:
    if os.environ.get("STRAWWU_SOFTWARE_SOURCES_FIXTURE") == "1":
        return True
    return not SOURCES_DIR.is_dir()


def read_fixture() -> dict[str, Any]:
    path = fixture_path()
    if not path.is_file():
        return {"schema": "strawwu-software-sources-fixture/v1", "mock": True, "sources": []}
    data = json.loads(path.read_text(encoding="utf-8"))
    data.setdefault("mock", True)
    return data


def parse_deb822(text: str) -> dict[str, str]:
    """Minimal deb822 parser for APT .sources files."""
    fields: dict[str, str] = {}
    current_key = ""
    current_val: list[str] = []

    def flush() -> None:
        nonlocal current_key, current_val
        if current_key:
            fields[current_key] = "\n".join(current_val).strip()
        current_key = ""
        current_val = []

    for raw in text.splitlines():
        if not raw.strip():
            continue
        if raw[0] not in " \t" and ":" in raw:
            flush()
            key, _, val = raw.partition(":")
            current_key = key.strip()
            current_val = [val.strip()]
        elif current_key:
            current_val.append(raw.strip())
    flush()
    return fields


def source_enabled(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.suffix == ".disabled":
        return False
    text = path.read_text(encoding="utf-8", errors="replace")
    fields = parse_deb822(text)
    enabled = fields.get("Enabled", "yes").lower()
    return enabled not in ("no", "false", "0")


def apt_source_entry(path: Path) -> dict[str, Any] | None:
    if path.suffix == ".disabled":
        active = path.with_suffix("")
        if active.suffix == ".sources":
            path = active
        else:
            return None
    if not path.is_file():
        return None

    text = path.read_text(encoding="utf-8", errors="replace")
    fields = parse_deb822(text)
    uri = fields.get("URIs", fields.get("URI", ""))
    if not uri:
        return None

    name = path.name
    source_id = re.sub(r"[^a-z0-9]+", "-", path.stem.lower()).strip("-") or "apt-source"
    suites = fields.get("Suites", fields.get("Suite", ""))
    components = fields.get("Components", fields.get("Component", "main"))

    readonly = False
    category = "third-party"
    if "strawwu" in uri.lower() or "strawwu" in name.lower():
        category = "strawwu"
        if source_id == "strawwu" or source_id == "strawwu-official":
            source_id = "strawwu-official"
    elif "security.ubuntu.com" in uri.lower() or "-security" in suites:
        category = "security"
        source_id = "ubuntu-security"
        readonly = True

    enabled = source_enabled(path)
    label = fields.get("Description") or path.stem.replace("-", " ").title()
    if source_id == "strawwu-official":
        label = "StrawWU Official Repository"
    elif source_id == "ubuntu-security":
        label = "Ubuntu Security Updates"

    return {
        "id": source_id,
        "label": label,
        "type": "apt",
        "uri": uri.split()[0] if uri else "",
        "suites": suites,
        "components": components,
        "enabled": enabled,
        "readonly": readonly,
        "category": category,
        "file": str(path),
    }


def scan_apt_sources() -> list[dict[str, Any]]:
    if not SOURCES_DIR.is_dir():
        return []

    entries: dict[str, dict[str, Any]] = {}
    for path in sorted(SOURCES_DIR.iterdir()):
        if path.name.startswith("."):
            continue
        if path.suffix in (".sources", ".list") or path.name.endswith(".sources.disabled"):
            entry = apt_source_entry(path)
            if entry:
                entries[entry["id"]] = entry

    # Ensure readonly security source appears even if only in ubuntu.sources template
    if "ubuntu-security" not in entries:
        ubuntu = SOURCES_DIR / "ubuntu.sources"
        if ubuntu.is_file():
            text = ubuntu.read_text(encoding="utf-8", errors="replace")
            if "security.ubuntu.com" in text or "Suites:" in text:
                entries["ubuntu-security"] = {
                    "id": "ubuntu-security",
                    "label": "Ubuntu Security Updates",
                    "type": "apt",
                    "uri": "http://security.ubuntu.com/ubuntu",
                    "suites": "resolute-security",
                    "components": "main restricted universe multiverse",
                    "enabled": source_enabled(ubuntu),
                    "readonly": True,
                    "category": "security",
                    "file": str(ubuntu),
                }

    return list(entries.values())


def scan_flatpak_remotes() -> list[dict[str, Any]]:
    if not shutil.which("flatpak"):
        return []

    try:
        proc = subprocess.run(
            ["flatpak", "remotes", "--columns=name,url", "--plain"],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []

    remotes: list[dict[str, Any]] = []
    for line in (proc.stdout or "").splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        name, url = parts[0].strip(), parts[1].strip()
        remotes.append(
            {
                "id": name if name != "flathub" else "flathub",
                "label": "Flathub" if name == "flathub" else name.title(),
                "type": "flatpak",
                "uri": url,
                "enabled": True,
                "readonly": name == "flathub",
                "category": "flatpak",
                "remote": name,
            }
        )
    return remotes


def list_sources() -> dict[str, Any]:
    if use_fixture_mode():
        data = read_fixture()
        return {
            "sources": data.get("sources", []),
            "mock": True,
            "upgradable_count": data.get("upgradable_count"),
            "last_check": data.get("last_check"),
        }

    sources = scan_apt_sources()
    flatpak = scan_flatpak_remotes()
    known_ids = {s["id"] for s in sources}
    for remote in flatpak:
        if remote["id"] not in known_ids:
            sources.append(remote)

    return {"sources": sources, "mock": False}


def _find_source(source_id: str, sources: list[dict[str, Any]]) -> dict[str, Any] | None:
    for src in sources:
        if src["id"] == source_id:
            return src
    return None


def _toggle_apt_file(path: Path, enabled: bool) -> None:
    disabled = Path(str(path) + ".disabled")
    if enabled:
        if disabled.is_file() and not path.is_file():
            disabled.rename(path)
        elif path.is_file():
            text = path.read_text(encoding="utf-8", errors="replace")
            if re.search(r"^Enabled:\s*no\b", text, re.MULTILINE | re.IGNORECASE):
                text = re.sub(
                    r"^Enabled:\s*no\b",
                    "Enabled: yes",
                    text,
                    count=1,
                    flags=re.MULTILINE | re.IGNORECASE,
                )
                path.write_text(text, encoding="utf-8")
    else:
        if path.is_file():
            text = path.read_text(encoding="utf-8", errors="replace")
            if "Enabled:" in text:
                text = re.sub(
                    r"^Enabled:\s*yes\b",
                    "Enabled: no",
                    text,
                    count=1,
                    flags=re.MULTILINE | re.IGNORECASE,
                )
                path.write_text(text, encoding="utf-8")
            else:
                path.rename(disabled)


def toggle_source(source_id: str, enabled: bool, *, dry_run: bool = False) -> dict[str, Any]:
    if source_id in READONLY_IDS:
        return {
            "success": False,
            "error": f"Source {source_id!r} is read-only",
            "code": ERROR_CODE,
        }

    if use_fixture_mode():
        data = read_fixture()
        src = _find_source(source_id, data.get("sources", []))
        if not src:
            return {"success": False, "error": f"Unknown source {source_id!r}", "code": ERROR_CODE}
        if src.get("readonly"):
            return {"success": False, "error": "Read-only source", "code": ERROR_CODE}
        src["enabled"] = enabled
        log_event("info", "toggle fixture", source_id=source_id, enabled=enabled)
        return {"success": True, "mock": True, "source_id": source_id, "enabled": enabled}

    listing = list_sources()
    src = _find_source(source_id, listing["sources"])
    if not src:
        return {"success": False, "error": f"Unknown source {source_id!r}", "code": ERROR_CODE}
    if src.get("readonly"):
        return {"success": False, "error": "Read-only source", "code": ERROR_CODE}
    if src.get("type") == "flatpak":
        return {"success": False, "error": "Flatpak remotes cannot be toggled here", "code": ERROR_CODE}

    path = Path(src.get("file", ""))
    if not path.is_file() and not Path(str(path) + ".disabled").is_file():
        return {"success": False, "error": f"Source file missing: {path}", "code": ERROR_CODE}

    if dry_run:
        return {"success": True, "dry_run": True, "source_id": source_id, "enabled": enabled}

    try:
        _toggle_apt_file(path, enabled)
        log_event("info", "source toggled", source_id=source_id, enabled=enabled, file=str(path))
        return {"success": True, "source_id": source_id, "enabled": enabled}
    except OSError as exc:
        log_event("error", "toggle failed", source_id=source_id, error=str(exc))
        return {"success": False, "error": str(exc), "code": ERROR_CODE}


def check_updates(*, refresh: bool = True) -> dict[str, Any]:
    if use_fixture_mode():
        data = read_fixture()
        count = int(data.get("upgradable_count", 0))
        return {
            "success": True,
            "mock": True,
            "upgradable": count,
            "checked_at": utc_now(),
        }

    if os.environ.get("STRAWWU_SOFTWARE_SOURCES_DRY_RUN") == "1":
        return {"success": True, "dry_run": True, "upgradable": 0, "checked_at": utc_now()}

    notifier = shutil.which(UPDATE_NOTIFIER)
    if not notifier:
        return {"success": False, "error": f"{UPDATE_NOTIFIER} not found", "code": ERROR_CODE}

    args = [notifier, "check"]
    try:
        proc = subprocess.run(args, capture_output=True, text=True, check=False, timeout=180)
        count = 0
        for line in (proc.stdout or "").splitlines():
            if line.startswith("upgradable="):
                count = int(line.split("=", 1)[1])
        log_event("info", "update check", upgradable=count, refresh=refresh)
        return {"success": True, "upgradable": count, "checked_at": utc_now()}
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        return {"success": False, "error": str(exc), "code": ERROR_CODE}


def source_status() -> dict[str, Any]:
    listing = list_sources()
    enabled = sum(1 for s in listing["sources"] if s.get("enabled"))
    readonly = sum(1 for s in listing["sources"] if s.get("readonly"))
    return {
        **listing,
        "summary": {
            "total": len(listing["sources"]),
            "enabled": enabled,
            "readonly": readonly,
        },
        "polkit_action": POLKIT_ACTION,
        "update_notifier": UPDATE_NOTIFIER,
    }


def cmd_version() -> int:
    print(PKG_VERSION)
    return 0


def run_cli(
    command: str | None,
    *,
    source_id: str = "",
    enabled: bool | None = None,
    as_json: bool = False,
    dry_run: bool = False,
) -> int:
    result: dict[str, Any]
    if command in (None, "list", "status"):
        result = source_status() if command == "status" else list_sources()
    elif command == "toggle":
        if not source_id or enabled is None:
            result = {"success": False, "error": "toggle requires source_id and --enable|--disable"}
        else:
            result = toggle_source(source_id, enabled, dry_run=dry_run)
    elif command == "check-updates":
        result = check_updates()
    else:
        result = {"success": False, "error": f"Unknown command {command!r}"}

    if as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif command == "check-updates" and result.get("success"):
        print(f"upgradable={result.get('upgradable', 0)}")
    elif command == "toggle" and result.get("success"):
        print(f"ok {source_id} enabled={result.get('enabled')}")
    elif not as_json and result.get("error"):
        print(result["error"], file=sys.stderr)

    if result.get("success") is False or result.get("error"):
        return 1
    return 0

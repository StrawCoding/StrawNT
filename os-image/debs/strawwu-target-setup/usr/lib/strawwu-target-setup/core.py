"""StrawWU target setup — Calamares chroot hook and rescue repair."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG_PATH = Path("/var/log/strawwu/target-setup.log")
MANIFEST_PATH = Path("/usr/share/strawwu/target-setup/target-manifest.yaml")
STAGED_DEBS_DIR = Path("/usr/share/strawwu/target-setup/staged-debs")
ERROR_CODE = "SWU-IN-002"
PKG_VERSION = "0.5.0.0-target"


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


def _parse_simple_yaml(text: str) -> dict[str, Any]:
    root: dict[str, Any] = {}
    current_list: list[str] | None = None
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
    return root


def load_manifest(path: Path | None = None) -> list[str]:
    target = path or MANIFEST_PATH
    if not target.exists():
        return []
    data = _parse_simple_yaml(target.read_text(encoding="utf-8"))
    packages = data.get("packages", [])
    if not isinstance(packages, list):
        return []
    return [str(p) for p in packages]


def deb_search_dirs() -> list[Path]:
    dirs: list[Path] = []
    override = os.environ.get("STRAWWU_TARGET_DEB_DIR")
    if override:
        dirs.append(Path(override))
    dirs.extend(
        [
            STAGED_DEBS_DIR,
            Path("/tmp/strawwu-target-debs"),
        ]
    )
    return dirs


def find_deb_file(package: str) -> Path | None:
    pattern = re.compile(rf"^{re.escape(package)}_[^/]+\.deb$")
    for directory in deb_search_dirs():
        if not directory.is_dir():
            continue
        for deb in sorted(directory.glob("*.deb")):
            if pattern.match(deb.name):
                return deb
    return None


def run_cmd(args: list[str], *, dry_run: bool = False) -> subprocess.CompletedProcess[str]:
    log_event("info", "exec", cmd=args, dry_run=dry_run)
    if dry_run:
        return subprocess.CompletedProcess(args, 0, "", "")
    return subprocess.run(args, capture_output=True, text=True, check=False)


def initd_cmd(*args: str, dry_run: bool = False) -> int:
    proc = run_cmd(["/usr/bin/strawwu-initd", *args], dry_run=dry_run)
    if proc.returncode != 0 and not dry_run:
        log_event(
            "error",
            "initd failed",
            args=list(args),
            stderr=proc.stderr.strip(),
            code=ERROR_CODE,
        )
    return proc.returncode


def set_lifecycle(phase: str, value: str, *, dry_run: bool = False) -> bool:
    rc = initd_cmd("set", f"lifecycle.{phase}", value, dry_run=dry_run)
    return rc == 0


def install_staged_debs(packages: list[str], *, dry_run: bool = False) -> bool:
    ok = True

    for pkg in packages:
        deb = find_deb_file(pkg)
        if deb is None:
            if _dpkg_installed(pkg):
                log_event("info", "package already installed", package=pkg)
                continue
            log_event("warn", "staged deb missing", package=pkg)
            ok = False
            continue

        extra: list[str] = []
        if pkg == "strawwu-desktop":
            extra = ["--force-depends"]

        cmd = ["dpkg", "-i", *extra, str(deb)]
        proc = run_cmd(cmd, dry_run=dry_run)
        if proc.returncode != 0 and not dry_run:
            log_event(
                "error",
                "dpkg install failed",
                package=pkg,
                stderr=proc.stderr.strip(),
                stdout=proc.stdout.strip(),
                code=ERROR_CODE,
            )
            ok = False

    return ok or dry_run


def _dpkg_installed(package: str) -> bool:
    proc = subprocess.run(
        ["dpkg-query", "-W", "-f=${Status}", package],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode == 0 and "ok installed" in proc.stdout


def configure_gdm_session(*, dry_run: bool = False) -> None:
    custom = Path("/etc/gdm3/custom.conf")
    if not custom.exists():
        log_event("info", "gdm3 custom.conf absent; skip default session")
        return
    text = custom.read_text(encoding="utf-8") if custom.exists() else ""
    if "strawwu-session" in text:
        log_event("info", "gdm default session already set")
        return
    block = "\n[daemon]\nDefaultSession=strawwu-session\n"
    if dry_run:
        log_event("info", "would set GDM DefaultSession=strawwu-session")
        return
    if "[daemon]" in text:
        if "DefaultSession=" in text:
            text = re.sub(r"DefaultSession=.*", "DefaultSession=strawwu-session", text)
        else:
            text = text.replace("[daemon]", "[daemon]\nDefaultSession=strawwu-session", 1)
    else:
        text = text.rstrip() + block
    custom.write_text(text, encoding="utf-8")
    log_event("info", "gdm DefaultSession=strawwu-session")


def enable_boot_selfcheck(*, dry_run: bool = False) -> None:
    unit = Path("/etc/systemd/system/strawwu-boot-selfcheck.service")
    if not unit.exists():
        log_event("info", "boot-selfcheck unit absent; skip enable")
        return
    run_cmd(["systemctl", "enable", "strawwu-boot-selfcheck.service"], dry_run=dry_run)


def run_target_setup(*, repair_only: bool = False, dry_run: bool = False) -> int:
    log_event("info", "target-setup start", repair_only=repair_only, dry_run=dry_run)

    if repair_only:
        if initd_cmd("repair", dry_run=dry_run) != 0:
            return 1
        packages = load_manifest()
        if not install_staged_debs(packages, dry_run=dry_run):
            return 1
        if initd_cmd("validate", dry_run=dry_run) != 0:
            return 1
        log_event("info", "target-setup repair complete")
        return 0

    if initd_cmd("init", dry_run=dry_run) != 0:
        return 1

    set_lifecycle("install", "installed", dry_run=dry_run)
    if not set_lifecycle("target_setup", "running", dry_run=dry_run):
        set_lifecycle("target_setup", "failed", dry_run=dry_run)
        return 1

    packages = load_manifest()
    if not install_staged_debs(packages, dry_run=dry_run):
        set_lifecycle("target_setup", "failed", dry_run=dry_run)
        return 1

    configure_gdm_session(dry_run=dry_run)
    enable_boot_selfcheck(dry_run=dry_run)

    if not set_lifecycle("target_setup", "done", dry_run=dry_run):
        return 1

    if initd_cmd("validate", dry_run=dry_run) != 0:
        return 1

    log_event("info", "target-setup complete")
    return 0


def cmd_version() -> int:
    print(f"strawwu-target-setup {PKG_VERSION} (log: {LOG_PATH})")
    return 0

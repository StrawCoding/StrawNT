#!/usr/bin/env python3
"""Split and splice Ubuntu multi-phase casper initrd (cpio + zstd-compressed main)."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PREFIX_PHASES = ("early", "early2", "early3")
DEFAULT_OVERLAYS_ROOT = Path(__file__).resolve().parent.parent / "initrd/overlays"
DEFAULT_LIVE_INIT_ROOT = Path(__file__).resolve().parent.parent / "initrd/strawwu-live-init"
DEFAULT_LIVE_BOTTOM_ROOT = Path(__file__).resolve().parent.parent / "initrd/strawwu-live-bottom"


def align4(value: int) -> int:
    return (value + 3) & ~3


def align512(value: int) -> int:
    return (value + 511) & ~511


def split_prefix_phases(initrd_path: Path, out_dir: Path) -> tuple[list[Path], Path | None]:
    data = initrd_path.read_bytes()
    offset = 0
    blobs: list[Path] = []
    out_dir.mkdir(parents=True, exist_ok=True)

    for phase in PREFIX_PHASES:
        if offset >= len(data) or data[offset : offset + 6] != b"070701":
            raise ValueError(f"expected cpio phase {phase} at offset {offset} in {initrd_path}")

        start = offset
        while True:
            namesize = int(data[offset + 94 : offset + 102], 16)
            filesize = int(data[offset + 54 : offset + 62], 16)
            name = (
                data[offset + 110 : offset + 110 + namesize - 1]
                .split(b"\0", 1)[0]
                .decode("ascii", "replace")
            )
            offset += align4(110 + namesize) + align4(filesize)
            if name == "TRAILER!!!":
                break

        end = align512(offset)
        blob = out_dir / f"{phase}.cpio.bin"
        blob.write_bytes(data[start:end])
        blobs.append(blob)
        offset = end

    main_blob: Path | None = None
    if offset < len(data):
        main_blob = out_dir / "main.zst"
        main_blob.write_bytes(data[offset:])

    return blobs, main_blob


def repack_main(main_dir: Path, out_cpio: Path) -> None:
    out_cpio.parent.mkdir(parents=True, exist_ok=True)
    with out_cpio.open("wb") as handle:
        find = subprocess.Popen(
            ["find", ".", "-print0"],
            cwd=main_dir,
            stdout=subprocess.PIPE,
        )
        cpio = subprocess.Popen(
            ["cpio", "--null", "-o", "--format=newc", "--quiet"],
            cwd=main_dir,
            stdin=find.stdout,
            stdout=handle,
            env={**os.environ, "LC_ALL": "C"},
        )
        find.stdout.close()  # type: ignore[union-attr]
        cpio.wait()
        find.wait()
        if cpio.returncode != 0 or find.returncode != 0:
            raise RuntimeError("failed to repack initrd main phase")


def compress_main_cpio(main_cpio: Path, out_zst: Path, level: int = 19) -> None:
    subprocess.run(
        ["zstd", f"-{level}", "-T0", "-f", str(main_cpio), "-o", str(out_zst)],
        check=True,
    )


def concat_initrd(prefix_blobs: list[Path], main_payload: Path, out_initrd: Path) -> None:
    with out_initrd.open("wb") as handle:
        for blob in prefix_blobs:
            handle.write(blob.read_bytes())
        handle.write(main_payload.read_bytes())


def extract_cpio_blob(blob: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    with blob.open("rb") as handle:
        subprocess.run(
            ["cpio", "-id", "--quiet", "--no-absolute-filenames"],
            cwd=out_dir,
            stdin=handle,
            check=True,
        )


def repack_cpio_dir(src_dir: Path, out_blob: Path) -> None:
    out_blob.parent.mkdir(parents=True, exist_ok=True)
    with out_blob.open("wb") as handle:
        find = subprocess.Popen(
            ["find", ".", "-print0"],
            cwd=src_dir,
            stdout=subprocess.PIPE,
        )
        cpio = subprocess.Popen(
            ["cpio", "--null", "-o", "--format=newc", "--quiet"],
            cwd=src_dir,
            stdin=find.stdout,
            stdout=handle,
            env={**os.environ, "LC_ALL": "C"},
        )
        find.stdout.close()  # type: ignore[union-attr]
        cpio.wait()
        find.wait()
        if cpio.returncode != 0 or find.returncode != 0:
            raise RuntimeError(f"failed to repack cpio: {out_blob}")

    size = out_blob.stat().st_size
    pad = align512(size) - size
    if pad:
        with out_blob.open("ab") as handle:
            handle.write(b"\0" * pad)


def module_stem(name: str) -> str:
    for suffix in (".ko.zst", ".ko.xz", ".ko"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def module_suffix(name: str) -> str:
    for suffix in (".ko.zst", ".ko.xz", ".ko"):
        if name.endswith(suffix):
            return suffix
    return ".ko"


def transform_dep_to_zst(content: str) -> str:
    import re

    # Noble casper initrd already ships .ko.zst paths; do not double-suffix.
    if ".ko.zst" in content:
        return content
    return re.sub(r"\.ko(\b|:| )", r".ko.zst\1", content)


def retarget_main_module_metadata(
    main_dir: Path,
    old_kver: str,
    new_kver: str,
    modules_src: Path,
) -> None:
    """Retarget casper initrd main metadata to strawwu kver without bloating deps."""
    import shutil

    meta_base = main_dir / "lib/modules"
    if not meta_base.is_dir():
        return

    old_dir = meta_base / old_kver
    new_dir = meta_base / new_kver
    if not old_dir.is_dir():
        if new_dir.is_dir():
            for name in ("modules.builtin", "modules.builtin.modinfo"):
                src = modules_src / name
                if src.is_file():
                    shutil.copy2(src, new_dir / name)
            for stale in new_dir.glob("*.bin"):
                stale.unlink()
        return

    if new_dir.exists():
        shutil.rmtree(new_dir)
    new_dir.mkdir(parents=True)

    text_meta = ("modules.dep", "modules.alias", "modules.softdep", "modules.symbols")
    for name in text_meta:
        src = old_dir / name
        if src.is_file():
            (new_dir / name).write_text(transform_dep_to_zst(src.read_text()))

    for name in (
        "modules.builtin",
        "modules.builtin.modinfo",
        "modules.order",
        "modules.devname",
    ):
        src = modules_src / name
        if src.is_file():
            shutil.copy2(src, new_dir / name)
        elif (old_dir / name).is_file():
            shutil.copy2(old_dir / name, new_dir / name)

    # Stale modules.*.bin from upstream kver breaks modprobe (overlay/isofs load fail).
    shutil.rmtree(old_dir)


CRITICAL_MAIN_MODULES = (
    "kernel/fs/isofs/isofs.ko",
    "kernel/fs/overlayfs/overlay.ko",
    "kernel/fs/squashfs/squashfs.ko",
)


def mirror_critical_modules_to_main(
    main_dir: Path,
    modules_src: Path,
    new_kver: str,
) -> None:
    """Duplicate live-boot fs modules into main for modprobe/insmod during casper."""
    dest_root = main_dir / "usr/lib/modules" / new_kver
    for rel in CRITICAL_MAIN_MODULES:
        src_ko = modules_src / rel
        if not src_ko.is_file():
            continue
        dest = dest_root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.is_file():
            write_module_payload(src_ko, dest)
        dest_zst = dest_root / f"{rel}.zst"
        if not dest_zst.is_file():
            write_module_payload(src_ko, dest_zst)


def resolve_overlays_root(overlays_root: Path | None) -> Path | None:
    if overlays_root is not None and overlays_root.is_dir() and (overlays_root / "scripts").is_dir():
        return overlays_root
    if DEFAULT_OVERLAYS_ROOT.is_dir() and (DEFAULT_OVERLAYS_ROOT / "scripts").is_dir():
        return DEFAULT_OVERLAYS_ROOT
    return None


def ensure_hook_order(main_dir: Path, hook_dir: str, hook_names: list[str]) -> None:
    order = main_dir / "scripts" / hook_dir / "ORDER"
    existing = order.read_text() if order.is_file() else ""
    prefix_lines: list[str] = []
    for hook_name in hook_names:
        needle = f"/scripts/{hook_dir}/{hook_name}"
        if needle not in existing:
            prefix_lines.append(f'{needle} "$@"')
    if prefix_lines:
        order.write_text("\n".join(prefix_lines + ([existing.rstrip()] if existing.strip() else [])) + "\n")


def resolve_live_init_root(live_init_root: Path | None) -> Path | None:
    if live_init_root is not None and (live_init_root / "scripts/strawwu-live-init").is_file():
        return live_init_root
    if (DEFAULT_LIVE_INIT_ROOT / "scripts/strawwu-live-init").is_file():
        return DEFAULT_LIVE_INIT_ROOT
    return None


def inject_strawwu_live_init(main_dir: Path, live_init_root: Path | None = None) -> None:
    """Replace upstream casper core with repo-owned strawwu-live-init fork."""
    import shutil

    root = resolve_live_init_root(live_init_root)
    if root is None:
        return

    live_init_src = root / "scripts/strawwu-live-init"
    live_init_dest = main_dir / "scripts/strawwu-live-init"
    live_init_dest.parent.mkdir(parents=True, exist_ok=True)
    if live_init_dest.exists() or live_init_dest.is_symlink():
        live_init_dest.unlink()
    shutil.copy2(live_init_src, live_init_dest)
    live_init_dest.chmod(0o755)

    casper_dest = main_dir / "scripts/casper"
    wrapper_src = root / "scripts/casper-wrapper"
    casper_dest.parent.mkdir(parents=True, exist_ok=True)
    if casper_dest.exists() or casper_dest.is_symlink():
        casper_dest.unlink()
    if wrapper_src.is_file():
        shutil.copy2(wrapper_src, casper_dest)
    else:
        casper_dest.write_text(
            "#!/bin/sh\n"
            "# StrawWU: boot=casper compat — delegate to strawwu-live-init\n"
            ". /scripts/strawwu-live-init\n"
        )
    casper_dest.chmod(0o755)


def resolve_live_bottom_root(live_bottom_root: Path | None) -> Path | None:
    if live_bottom_root is not None and (live_bottom_root / "scripts/ORDER").is_file():
        return live_bottom_root
    if (DEFAULT_LIVE_BOTTOM_ROOT / "scripts/ORDER").is_file():
        return DEFAULT_LIVE_BOTTOM_ROOT
    return None


def inject_strawwu_live_bottom(main_dir: Path, live_bottom_root: Path | None = None) -> None:
    """Replace upstream casper-bottom hooks with repo-owned strawwu-live-bottom fork."""
    import shutil

    root = resolve_live_bottom_root(live_bottom_root)
    if root is None:
        return

    scripts_src = root / "scripts"
    dest = main_dir / "scripts/strawwu-live-bottom"
    if dest.exists():
        shutil.rmtree(dest)
    inject_tree_into_dir(dest, scripts_src)
    for hook in dest.iterdir():
        if hook.is_file() and hook.name != "ORDER":
            hook.chmod(0o755)

    casper_bottom = main_dir / "scripts/casper-bottom"
    if casper_bottom.exists():
        shutil.rmtree(casper_bottom)
    casper_bottom.mkdir(parents=True)
    order_src = dest / "ORDER"
    if order_src.is_file():
        # boot=casper compat: casper-bottom ORDER delegates to strawwu-live-bottom hooks.
        (casper_bottom / "ORDER").write_text(order_src.read_text())


def inject_initrd_overlays(main_dir: Path, overlays_root: Path | None) -> None:
    root = resolve_overlays_root(overlays_root)
    if root is None:
        return
    scripts_src = root / "scripts"
    if not scripts_src.is_dir():
        return
    for hook_dir in sorted(p for p in scripts_src.iterdir() if p.is_dir()):
        if hook_dir.name == "casper-bottom":
            continue
        inject_tree_into_dir(main_dir / "scripts" / hook_dir.name, hook_dir)
        strawwu_hooks = sorted(
            p.name
            for p in hook_dir.iterdir()
            if p.is_file() and p.name.startswith(("05strawwu", "20iso_scan"))
        )
        if strawwu_hooks:
            ensure_hook_order(main_dir, hook_dir.name, strawwu_hooks)


def inject_casper_premount_hooks(main_dir: Path, branding_root: Path | None) -> None:
    """Backward-compatible wrapper; overlays live under os-image/initrd/overlays/."""
    inject_initrd_overlays(main_dir, None)


def install_main_module_metadata(main_dir: Path, new_kver: str, modules_src: Path) -> None:
    """Noble casper main carries lib/modules/<kver> metadata; early3 holds .ko.zst payloads."""
    import shutil

    for rel_base in (Path("lib/modules"), Path("usr/lib/modules")):
        base = main_dir / rel_base
        if not base.is_dir():
            continue
        for child in list(base.iterdir()):
            if child.is_dir():
                shutil.rmtree(child)

    meta_dir = main_dir / "lib/modules" / new_kver
    meta_dir.mkdir(parents=True, exist_ok=True)

    text_meta = ("modules.dep", "modules.alias", "modules.softdep", "modules.symbols")
    for name in text_meta:
        src = modules_src / name
        if src.is_file():
            (meta_dir / name).write_text(transform_dep_to_zst(src.read_text()))

    for name in (
        "modules.builtin",
        "modules.builtin.modinfo",
        "modules.order",
        "modules.devname",
    ):
        src = modules_src / name
        if src.is_file():
            shutil.copy2(src, meta_dir / name)

    for name in (
        "modules.dep.bin",
        "modules.alias.bin",
        "modules.symbols.bin",
        "modules.builtin.bin",
        "modules.builtin.alias.bin",
    ):
        src = modules_src / name
        if src.is_file():
            shutil.copy2(src, meta_dir / name)


def write_module_payload(src_ko: Path, dest_path: Path) -> None:
    """Write a kernel module into initrd early3 using upstream compression layout."""
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    if dest_path.name.endswith(".ko.zst"):
        subprocess.run(
            ["zstd", "-19", "-T0", "-f", str(src_ko), "-o", str(dest_path)],
            check=True,
        )
    elif dest_path.name.endswith(".ko.xz"):
        subprocess.run(["xz", "-9", "-f", "-k", str(src_ko)], check=True)
        src_ko.with_suffix(".ko.xz").replace(dest_path)
    else:
        dest_path.write_bytes(src_ko.read_bytes())


def replace_modules_tree(modules_root: Path, old_kver: str, new_kver: str, modules_src: Path) -> None:
    old_dir = modules_root / old_kver
    new_dir = modules_root / new_kver
    if not old_dir.is_dir():
        raise ValueError(f"initrd modules missing: {old_dir}")
    if not modules_src.is_dir():
        raise ValueError(f"kernel modules missing: {modules_src}")

    if new_dir.exists():
        import shutil

        shutil.rmtree(new_dir)
    new_dir.mkdir(parents=True)
    src_by_stem = {
        module_stem(mod.name): mod for mod in modules_src.rglob("*") if mod.is_file() and ".ko" in mod.name
    }

    # Noble casper early3 carries only compressed .ko.* under kernel/ — no modules.dep.
    for mod in old_dir.rglob("*"):
        if not mod.is_file() or ".ko" not in mod.name:
            continue
        rel = mod.relative_to(old_dir)
        src_ko = src_by_stem.get(module_stem(mod.name))
        if src_ko is None:
            continue
        target = new_dir / rel.parent / mod.name
        if target.exists() or target.is_symlink():
            target.unlink()
        write_module_payload(src_ko, target)

    if old_dir != new_dir and old_dir.exists():
        import shutil

        shutil.rmtree(old_dir)


def replace_early3_modules(
    initrd_src: Path,
    scratch: Path,
    new_kver: str,
    modules_src: Path,
) -> tuple[Path | None, str]:
    prefix_dir = scratch / "prefix"
    prefix_dir.mkdir(parents=True, exist_ok=True)
    prefix_blobs, main_blob = split_prefix_phases(initrd_src, prefix_dir)
    if len(prefix_blobs) < 3:
        return main_blob, ""

    early3_blob = prefix_blobs[2]
    early3_dir = scratch / "early3"
    if early3_dir.exists():
        import shutil

        shutil.rmtree(early3_dir)
    extract_cpio_blob(early3_blob, early3_dir)

    modules_rel = Path("usr/lib/modules")
    if not (early3_dir / modules_rel).is_dir():
        modules_rel = Path("lib/modules")
    modules_root = early3_dir / modules_rel
    if not modules_root.is_dir():
        raise ValueError("early3 initrd has no modules tree")

    old_kvers = sorted(p.name for p in modules_root.iterdir() if p.is_dir())
    if not old_kvers:
        raise ValueError("early3 initrd has no module version directory")
    old_kver = old_kvers[0]
    replace_modules_tree(modules_root, old_kver, new_kver, modules_src)
    # Remove any leftover upstream kver trees (prevents dual 6.11 + 6.8.12 trees).
    for extra in old_kvers[1:]:
        extra_dir = modules_root / extra
        if extra_dir.is_dir():
            import shutil

            shutil.rmtree(extra_dir)
    for child in list(modules_root.iterdir()):
        if child.is_dir() and child.name != new_kver:
            import shutil

            shutil.rmtree(child)

    new_early3 = prefix_dir / "early3.cpio.bin"
    repack_cpio_dir(early3_dir, new_early3)
    prefix_blobs[2] = new_early3
    return main_blob, old_kver


def verify_initrd(initrd_path: Path) -> tuple[int, str]:
    with tempfile.TemporaryDirectory(prefix="initrd-verify-") as tmp:
        result = subprocess.run(
            ["unmkinitramfs", str(initrd_path), tmp],
            capture_output=True,
            text=True,
        )
        main = Path(tmp) / "main"
        size = "missing"
        if main.is_dir():
            size = subprocess.check_output(["du", "-sh", str(main)], text=True).split()[0]
        return result.returncode, size


def cmd_split(args: argparse.Namespace) -> int:
    blobs, main_blob = split_prefix_phases(Path(args.initrd), Path(args.out_dir))
    for blob in blobs:
        print(blob)
    if main_blob is not None:
        print(main_blob)
    return 0


def inject_tree_into_dir(target_root: Path, src_root: Path) -> None:
    import shutil

    for path in src_root.rglob("*"):
        if path.is_dir():
            continue
        rel = path.relative_to(src_root)
        dest = target_root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists() or dest.is_symlink():
            dest.unlink()
        if path.is_symlink():
            dest.symlink_to(os.readlink(path))
        else:
            shutil.copy2(path, dest)


def inject_plymouth_theme_tree(target_root: Path, branding_root: Path) -> None:
    import shutil

    theme_src = branding_root / "usr/share/plymouth/themes/strawwu-boot"
    plymouth_conf = branding_root / "etc/plymouth/plymouthd.conf"
    if not theme_src.is_dir():
        return
    theme_dest = target_root / "usr/share/plymouth/themes/strawwu-boot"
    if theme_dest.exists():
        shutil.rmtree(theme_dest)
    shutil.copytree(theme_src, theme_dest)
    conf_dest = target_root / "etc/plymouth"
    conf_dest.mkdir(parents=True, exist_ok=True)
    if plymouth_conf.is_file():
        shutil.copy2(plymouth_conf, conf_dest / "plymouthd.conf")
    default_link = target_root / "usr/share/plymouth/themes/default.plymouth"
    default_link.parent.mkdir(parents=True, exist_ok=True)
    if default_link.exists() or default_link.is_symlink():
        default_link.unlink()
    default_link.symlink_to("/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth")
    ubuntu_text = target_root / "usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth"
    if ubuntu_text.is_file():
        text = ubuntu_text.read_text()
        ubuntu_text.write_text(text.replace("title=Ubuntu", "title=StrawWU"))


def inject_plymouth_into_early3(early3_dir: Path, branding_root: Path) -> None:
    inject_plymouth_theme_tree(early3_dir, branding_root)


def inject_plymouth_into_main(main_dir: Path, branding_root: Path) -> None:
    inject_plymouth_theme_tree(main_dir, branding_root)


def patch_casper_live_media_hint(main_dir: Path) -> None:
    casper = main_dir / "scripts/casper"
    if not casper.is_file():
        return
    text = casper.read_text()
    needle = "find_livefs() {\n    timeout=\"${1}\""
    replacement = (
        "find_livefs() {\n"
        "    timeout=\"${1}\"\n"
        "    if [ -z \"${LIVEMEDIA}\" ]; then\n"
        "        for _dev in /dev/sr0 /dev/cdrom /dev/sr1; do\n"
        "            [ -b \"${_dev}\" ] || continue\n"
        "            LIVEMEDIA=\"${_dev}\"\n"
        "            export LIVEMEDIA\n"
        "            break\n"
        "        done\n"
        "    fi"
    )
    if needle in text and "for _dev in /dev/sr0" not in text:
        casper.write_text(text.replace(needle, replacement, 1))


def patch_casper_overlay_insmod(main_dir: Path) -> None:
    casper = main_dir / "scripts/casper"
    if not casper.is_file():
        return
    text = casper.read_text()
    replacement = (
        'grep -q "[[:space:]]overlay$" /proc/filesystems || '
        'modprobe "${MP_QUIET}" -b overlay 2>/dev/null || '
        'insmod "/usr/lib/modules/$(uname -r)/kernel/fs/overlayfs/overlay.ko" 2>/dev/null || '
        'grep -q "[[:space:]]overlay$" /proc/filesystems || '
        'panic "/cow format specified as \'overlay\' and no support found"'
    )
    needles = (
        'modprobe "${MP_QUIET}" -b overlay || panic "/cow format specified as \'overlay\' and no support found"',
        'modprobe "${MP_QUIET}" -b overlay || insmod "/usr/lib/modules/$(uname -r)/kernel/fs/overlayfs/overlay.ko" 2>/dev/null || panic "/cow format specified as \'overlay\' and no support found"',
    )
    if replacement in text:
        return
    for needle in needles:
        if needle in text:
            casper.write_text(text.replace(needle, replacement, 1))
            return


def patch_casper_conf_in_initrd(target_root: Path) -> None:
    conf = target_root / "etc/casper.conf"
    if not conf.is_file():
        return
    text = conf.read_text()
    replacements = {
        'export BUILD_SYSTEM="Ubuntu"': 'export BUILD_SYSTEM="StrawWU"',
        'export HOST="ubuntu"': 'export HOST="strawwu"',
        'export USERFULLNAME="Live session user"': 'export USERFULLNAME="StrawWU Live session user"',
        '# export FLAVOUR="Ubuntu"': 'export FLAVOUR="StrawWU"',
        'export FLAVOUR="Ubuntu"': 'export FLAVOUR="StrawWU"',
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    if 'export FLAVOUR=' not in text:
        text += '\nexport FLAVOUR="StrawWU"\n'
    conf.write_text(text)


def decompress_main_zst(main_blob: Path, main_dir: Path, scratch: Path) -> None:
    import shutil

    if main_dir.exists():
        shutil.rmtree(main_dir)
    main_dir.mkdir(parents=True)
    main_cpio = scratch / "main.decompressed.cpio"
    subprocess.run(["zstd", "-d", "-f", str(main_blob), "-o", str(main_cpio)], check=True)
    with main_cpio.open("rb") as handle:
        subprocess.run(
            ["cpio", "-id", "--quiet", "--no-absolute-filenames"],
            cwd=main_dir,
            stdin=handle,
            check=True,
        )


def recompress_main_dir(main_dir: Path, scratch: Path) -> Path:
    main_cpio = scratch / "main.repack.cpio"
    main_zst = scratch / "main.branded.zst"
    repack_main(main_dir, main_cpio)
    compress_main_cpio(main_cpio, main_zst, level=19)
    return main_zst


def regenerate_main_module_deps(main_dir: Path, new_kver: str) -> None:
    """Rebuild modules.dep.bin for mirrored live-boot modules (modprobe needs .bin)."""
    mod_root = main_dir / "lib/modules" / new_kver
    if not mod_root.is_dir():
        return
    subprocess.run(
        ["depmod", "-b", str(main_dir), new_kver],
        check=True,
    )


def sync_main_modules_tree(main_dir: Path, old_kver: str, new_kver: str, modules_src: Path) -> None:
    """Keep casper minimal modules.dep; only retarget kver + refresh builtins."""
    retarget_main_module_metadata(main_dir, old_kver, new_kver, modules_src)


def refresh_preserved_main(
    main_blob: Path,
    scratch: Path,
    branding_root: Path | None = None,
    modules_src: Path | None = None,
    new_kver: str = "",
    old_kver: str = "",
    overlays_root: Path | None = None,
) -> Path:
    main_dir = scratch / "main-brand"
    decompress_main_zst(main_blob, main_dir, scratch)
    if modules_src is not None and new_kver and modules_src.is_dir() and old_kver:
        sync_main_modules_tree(main_dir, old_kver, new_kver, modules_src)
        mirror_critical_modules_to_main(main_dir, modules_src, new_kver)
        regenerate_main_module_deps(main_dir, new_kver)
    inject_strawwu_live_init(main_dir)
    inject_strawwu_live_bottom(main_dir)
    inject_initrd_overlays(main_dir, overlays_root)
    if branding_root is not None and branding_root.is_dir():
        inject_plymouth_into_main(main_dir, branding_root)
        patch_casper_conf_in_initrd(main_dir)
    return recompress_main_dir(main_dir, scratch)


def repack_initrd_phases(
    initrd_src: Path,
    main_dir: Path,
    initrd_out: Path,
    scratch: Path,
    modules_src: Path | None = None,
    new_kver: str = "",
    preserve_main: bool = False,
    branding_root: Path | None = None,
    overlays_root: Path | None = None,
) -> None:
    main_blob: Path | None = None
    prefix_blobs: list[Path]
    prefix_dir = scratch / "prefix"
    prefix_dir.mkdir(parents=True, exist_ok=True)
    old_kver = ""

    if modules_src is not None and new_kver and modules_src.is_dir():
        main_blob, old_kver = replace_early3_modules(initrd_src, scratch, new_kver, modules_src)
        prefix_blobs = sorted(prefix_dir.glob("early*.cpio.bin"), key=lambda p: p.name)
        if branding_root is not None and branding_root.is_dir():
            early3_dir = scratch / "early3-brand"
            if early3_dir.exists():
                import shutil

                shutil.rmtree(early3_dir)
            extract_cpio_blob(prefix_blobs[2], early3_dir)
            inject_plymouth_into_early3(early3_dir, branding_root)
            new_early3 = prefix_dir / "early3.cpio.bin"
            repack_cpio_dir(early3_dir, new_early3)
            prefix_blobs[2] = new_early3
        preserve_main = True
    else:
        prefix_blobs, main_blob = split_prefix_phases(initrd_src, prefix_dir)

    if preserve_main:
        if main_blob is None or not main_blob.is_file():
            _, main_blob = split_prefix_phases(initrd_src, prefix_dir)
        if main_blob is None or not main_blob.is_file():
            raise RuntimeError("preserve-main requested but upstream main.zst missing")
        overlays_active = resolve_overlays_root(overlays_root) is not None
        if (
            overlays_active
            or (branding_root is not None and branding_root.is_dir())
            or (modules_src is not None and new_kver and modules_src.is_dir())
        ):
            main_blob = refresh_preserved_main(
                main_blob,
                scratch,
                branding_root,
                modules_src,
                new_kver,
                old_kver,
                overlays_root,
            )
        concat_initrd(prefix_blobs, main_blob, initrd_out)
        return

    main_cpio = scratch / "main.cpio"
    main_zst = scratch / "main.zst"
    repack_main(main_dir, main_cpio)
    compress_main_cpio(main_cpio, main_zst, level=19)
    concat_initrd(prefix_blobs, main_zst, initrd_out)


def cmd_repack_early3_only(args: argparse.Namespace) -> int:
    initrd_src = Path(args.initrd_src)
    initrd_out = Path(args.out_initrd)
    scratch = Path(args.scratch)
    modules_src = Path(args.modules_src)
    new_kver = args.new_kver
    branding_root = Path(args.branding_root) if args.branding_root else None
    overlays_root = Path(args.overlays_root) if args.overlays_root else None

    scratch.mkdir(parents=True, exist_ok=True)
    repack_initrd_phases(
        initrd_src,
        Path("/dev/null"),
        initrd_out,
        scratch,
        modules_src,
        new_kver,
        preserve_main=True,
        branding_root=branding_root,
        overlays_root=overlays_root,
    )
    return 0


def cmd_repack_main_only(args: argparse.Namespace) -> int:
    initrd_src = Path(args.initrd_src)
    main_dir = Path(args.main_dir)
    out_initrd = Path(args.out_initrd)
    scratch = Path(args.scratch)

    scratch.mkdir(parents=True, exist_ok=True)
    modules_src = Path(args.modules_src) if args.modules_src else None
    new_kver = args.new_kver or ""
    branding_root = Path(args.branding_root) if args.branding_root else None
    overlays_root = Path(args.overlays_root) if args.overlays_root else None
    preserve_main = bool(args.preserve_main) or (modules_src is not None and new_kver)
    repack_initrd_phases(
        initrd_src,
        main_dir,
        out_initrd,
        scratch,
        modules_src,
        new_kver,
        preserve_main=preserve_main,
        branding_root=branding_root,
        overlays_root=overlays_root,
    )
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    code, main_size = verify_initrd(Path(args.initrd))
    print(f"exit={code} main={main_size}")
    return code


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_split = sub.add_parser("split")
    p_split.add_argument("initrd")
    p_split.add_argument("out_dir")
    p_split.set_defaults(func=cmd_split)

    p_repack = sub.add_parser("repack-main-only")
    p_repack.add_argument("initrd_src")
    p_repack.add_argument("main_dir")
    p_repack.add_argument("out_initrd")
    p_repack.add_argument("scratch")
    p_repack.add_argument("--zstd-level", type=int, default=19)
    p_repack.add_argument("--modules-src", default="")
    p_repack.add_argument("--new-kver", default="")
    p_repack.add_argument("--preserve-main", action="store_true")
    p_repack.add_argument("--branding-root", default="")
    p_repack.add_argument("--overlays-root", default="")
    p_repack.set_defaults(func=cmd_repack_main_only)

    p_early3 = sub.add_parser("repack-early3-only")
    p_early3.add_argument("initrd_src")
    p_early3.add_argument("out_initrd")
    p_early3.add_argument("scratch")
    p_early3.add_argument("--modules-src", required=True)
    p_early3.add_argument("--new-kver", required=True)
    p_early3.add_argument("--branding-root", default="")
    p_early3.add_argument("--overlays-root", default="")
    p_early3.set_defaults(func=cmd_repack_early3_only)

    p_verify = sub.add_parser("verify")
    p_verify.add_argument("initrd")
    p_verify.set_defaults(func=cmd_verify)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

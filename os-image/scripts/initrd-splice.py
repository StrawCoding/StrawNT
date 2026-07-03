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

    return re.sub(r"\.ko(\b|:| )", r".ko.zst\1", content)


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
) -> Path | None:
    prefix_dir = scratch / "prefix"
    prefix_dir.mkdir(parents=True, exist_ok=True)
    prefix_blobs, main_blob = split_prefix_phases(initrd_src, prefix_dir)
    if len(prefix_blobs) < 3:
        return main_blob

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

    old_kver = next(p.name for p in modules_root.iterdir() if p.is_dir())
    replace_modules_tree(modules_root, old_kver, new_kver, modules_src)

    new_early3 = prefix_dir / "early3.cpio.bin"
    repack_cpio_dir(early3_dir, new_early3)
    prefix_blobs[2] = new_early3
    return main_blob


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


def sync_main_modules_tree(main_dir: Path, new_kver: str, modules_src: Path) -> None:
    """Caspar main phase runs modprobe from /lib/modules/$(uname -r) metadata."""
    install_main_module_metadata(main_dir, new_kver, modules_src)


def refresh_preserved_main(
    main_blob: Path,
    scratch: Path,
    branding_root: Path | None = None,
    modules_src: Path | None = None,
    new_kver: str = "",
) -> Path:
    main_dir = scratch / "main-brand"
    decompress_main_zst(main_blob, main_dir, scratch)
    if modules_src is not None and new_kver and modules_src.is_dir():
        sync_main_modules_tree(main_dir, new_kver, modules_src)
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
) -> None:
    main_blob: Path | None = None
    prefix_blobs: list[Path]
    prefix_dir = scratch / "prefix"
    prefix_dir.mkdir(parents=True, exist_ok=True)

    if modules_src is not None and new_kver and modules_src.is_dir():
        main_blob = replace_early3_modules(initrd_src, scratch, new_kver, modules_src)
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
        if (branding_root is not None and branding_root.is_dir()) or (
            modules_src is not None and new_kver and modules_src.is_dir()
        ):
            main_blob = refresh_preserved_main(
                main_blob,
                scratch,
                branding_root,
                modules_src,
                new_kver,
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
    p_repack.set_defaults(func=cmd_repack_main_only)

    p_early3 = sub.add_parser("repack-early3-only")
    p_early3.add_argument("initrd_src")
    p_early3.add_argument("out_initrd")
    p_early3.add_argument("scratch")
    p_early3.add_argument("--modules-src", required=True)
    p_early3.add_argument("--new-kver", required=True)
    p_early3.add_argument("--branding-root", default="")
    p_early3.set_defaults(func=cmd_repack_early3_only)

    p_verify = sub.add_parser("verify")
    p_verify.add_argument("initrd")
    p_verify.set_defaults(func=cmd_verify)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Ingest user-provided StrawWU logos and generate OS branding assets."""
from __future__ import annotations

import base64
import shutil
import subprocess
import sys
from pathlib import Path

BRAND = Path(__file__).resolve().parent
REPO_ROOT = BRAND.parents[2]
DEFAULT_SOURCE = Path("/mnt/data/Data/檔案/專案資料/StrawWU")

# User directory may ship legacy (strawwu-logo-*) or current (strawwu-*) names.
SOURCE_ALIASES: dict[str, tuple[str, ...]] = {
    "icon": ("strawwu-logo-icon.png", "strawwu-icon.png"),
    "primary": ("strawwu-logo-primary.png", "strawwu-primary.png", "strawwu-wordmark.png"),
    "momo": ("strawwu-logo-momo.png", "strawwu-momo.png"),
    "momo_light": ("strawwu-logo-momo-light.png", "strawwu-momo-light.png"),
}

COLORS = {
    "bg_deep": "#0A0E14",
    "bg_icon": "#0f1419",
    "linux": "#14B8A6",
    "win": "#F59E0B",
    "straw": "#D4A853",
    "bridge": "#60A5FA",
    "text": "#F4F6F9",
    "muted": "#A9B6C3",
}

ICON_SIZES = (16, 32, 48, 64, 128, 256, 512, 1024)
ICON_CORNER_RADIUS_PCT = 0.22
RECT_CORNER_RADIUS_PCT = 0.08


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, capture_output=True)


def image_size(path: Path) -> tuple[int, int]:
    out = subprocess.check_output(["identify", "-format", "%w %h", str(path)], text=True)
    w, h = out.strip().split()
    return int(w), int(h)


def apply_rounded_corners(src: Path, dst: Path, *, radius_pct: float) -> None:
    """Round PNG corners; radius_pct is relative to min(width, height)."""
    w, h = image_size(src)
    radius = max(4, int(min(w, h) * radius_pct))
    run(
        [
            "convert",
            str(src),
            "-alpha",
            "set",
            "(",
            "+clone",
            "-alpha",
            "extract",
            "-draw",
            f"fill black roundrectangle 0,0,{w - 1},{h - 1},{radius},{radius}",
            ")",
            "-alpha",
            "off",
            "-compose",
            "CopyOpacity",
            "-composite",
            str(dst),
        ]
    )
    print(f"rounded {dst} (r={radius}px)")


def write_transparent_png(path: Path, size: int = 1) -> None:
    run(["convert", "-size", f"{size}x{size}", "xc:none", str(path)])
    print(f"wrote transparent {path}")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    print(f"wrote {path}")


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"copied {src.name} -> {dst}")


def resolve_source(source_dir: Path, role: str) -> Path | None:
    for name in SOURCE_ALIASES[role]:
        candidate = source_dir / name
        if candidate.is_file():
            return candidate
    return None


def canonical_source_name(role: str, resolved: Path) -> str:
    mapping = {
        "icon": "strawwu-logo-icon.png",
        "primary": "strawwu-logo-primary.png",
        "momo": "strawwu-logo-momo.png",
        "momo_light": "strawwu-logo-momo-light.png",
    }
    return mapping[role]


def rasterize(src: Path, dst: Path, size: int, *, rounded: bool = True) -> None:
    tmp = dst.with_suffix(".tmp.png")
    run(
        [
            "convert",
            "-background",
            "none",
            str(src),
            "-resize",
            f"{size}x{size}",
            str(tmp),
        ]
    )
    if rounded:
        apply_rounded_corners(tmp, dst, radius_pct=ICON_CORNER_RADIUS_PCT)
        tmp.unlink(missing_ok=True)
    else:
        tmp.replace(dst)
    print(f"wrote {dst} ({size}px)")


def rasterize_width(src: Path, dst: Path, width: int, *, rounded: bool = True) -> None:
    tmp = dst.with_suffix(".tmp.png")
    run(
        [
            "convert",
            "-background",
            "none",
            str(src),
            "-resize",
            f"{width}x",
            str(tmp),
        ]
    )
    if rounded:
        apply_rounded_corners(tmp, dst, radius_pct=RECT_CORNER_RADIUS_PCT)
        tmp.unlink(missing_ok=True)
    else:
        tmp.replace(dst)
    print(f"wrote {dst} ({width}px wide)")


def mono_variant(src: Path, dst: Path, *, light: bool) -> None:
    color = "white" if light else "#0f172a"
    run(
        [
            "convert",
            "-background",
            "none",
            str(src),
            "-alpha",
            "set",
            "-channel",
            "RGBA",
            "-fuzz",
            "12%",
            "-fill",
            color,
            "-opaque",
            "none",
            "-colorspace",
            "Gray",
            "-fill",
            color,
            "-colorize",
            "100%",
            str(dst),
        ]
    )
    print(f"wrote {dst}")


def wrap_png_as_svg(png: Path, svg_out: Path, label: str, size: int | None = None) -> None:
    data = base64.b64encode(png.read_bytes()).decode("ascii")
    if size is None:
        out = subprocess.check_output(["identify", "-format", "%w %h", str(png)], text=True)
        w, h = out.strip().split()
    else:
        w = h = str(size)
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     viewBox="0 0 {w} {h}" role="img" aria-label="{label}">
  <image width="{w}" height="{h}" preserveAspectRatio="xMidYMid meet"
         xlink:href="data:image/png;base64,{data}"/>
</svg>
"""
    write_text(svg_out, svg)


def b64_data_uri(path: Path) -> str:
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    mime = "image/svg+xml" if path.suffix == ".svg" else "image/png"
    return f"data:{mime};base64,{data}"


def build_preview() -> str:
    icon_b64 = b64_data_uri(BRAND / "logo-icon.png")
    word_b64 = b64_data_uri(BRAND / "logo-wordmark.png")
    momo_b64 = b64_data_uri(BRAND / "source" / "strawwu-logo-momo.png")
    return f"""<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>StrawWU Branding Preview</title>
  <style>
    :root {{
      --bg: {COLORS['bg_deep']};
      --surface: #111820;
      --border: #243040;
      --text: {COLORS['text']};
      --muted: {COLORS['muted']};
      --linux: {COLORS['linux']};
      --win: {COLORS['win']};
      --straw: {COLORS['straw']};
      --bridge: {COLORS['bridge']};
    }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; font-family: "IBM Plex Sans", "Noto Sans TC", sans-serif;
            background: var(--bg); color: var(--text); line-height: 1.6; }}
    .wrap {{ max-width: 1100px; margin: 0 auto; padding: 32px 20px 64px; }}
    h1 {{ font-size: 1.75rem; font-weight: 600; margin: 0 0 8px; }}
    .sub {{ color: var(--muted); margin-bottom: 28px; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }}
    .card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 20px; }}
    .card h2 {{ margin: 0 0 12px; font-size: 0.95rem; color: var(--muted); font-weight: 500; }}
    .preview {{ display: flex; align-items: center; justify-content: center; min-height: 140px; }}
    .preview img {{ max-width: 100%; height: auto; border-radius: 22%; }}
    .swatch {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; margin-top: 20px; }}
    .chip {{ border: 1px solid var(--border); border-radius: 8px; padding: 10px; font-size: 0.85rem; }}
    .dot {{ width: 28px; height: 28px; border-radius: 6px; margin-bottom: 6px; }}
  </style>
</head>
<body>
  <div class="wrap">
    <h1>StrawWU Logo — 使用者提供</h1>
    <p class="sub">來源：/mnt/data/Data/檔案/專案資料/StrawWU</p>
    <div class="grid">
      <div class="card"><h2>主圖標</h2><div class="preview"><img src="{icon_b64}" width="180" alt="icon"/></div></div>
      <div class="card"><h2>橫式字標</h2><div class="preview"><img src="{word_b64}" style="max-width:100%" alt="wordmark"/></div></div>
      <div class="card"><h2>Momo 吉祥物</h2><div class="preview"><img src="{momo_b64}" style="max-width:100%" alt="momo"/></div></div>
    </div>
    <div class="card" style="margin-top:16px">
      <h2>色票</h2>
      <div class="swatch">
        <div class="chip"><div class="dot" style="background:{COLORS['linux']}"></div>Teal {COLORS['linux']}</div>
        <div class="chip"><div class="dot" style="background:{COLORS['win']}"></div>Amber {COLORS['win']}</div>
        <div class="chip"><div class="dot" style="background:{COLORS['straw']}"></div>Straw {COLORS['straw']}</div>
        <div class="chip"><div class="dot" style="background:{COLORS['bridge']}"></div>Bridge {COLORS['bridge']}</div>
        <div class="chip"><div class="dot" style="background:{COLORS['bg_deep']}"></div>BG {COLORS['bg_deep']}</div>
      </div>
    </div>
  </div>
</body>
</html>
"""


def sync_downstream_assets() -> None:
    """Mirror hub / component icons from generated branding."""
    icon_png = BRAND / "logo-icon.png"
    icon_svg = BRAND / "logo-icon.svg"
    dist_logo = BRAND / "usr/share/icons/hicolor/scalable/apps/distributor-logo.svg"
    for dest_dir in (
        REPO_ROOT / "hub" / "assets",
        REPO_ROOT / "components" / "strawwu-hub" / "assets",
    ):
        if not dest_dir.parent.is_dir():
            continue
        dest_dir.mkdir(parents=True, exist_ok=True)
        copy_file(icon_png, dest_dir / "icon.png")
        copy_file(icon_svg, dest_dir / "icon.svg")
    if icon_svg.is_file():
        copy_file(icon_svg, dist_logo)


def ingest(source_dir: Path) -> None:
    source_dir = source_dir.resolve()
    icon_png = resolve_source(source_dir, "icon")
    primary_png = resolve_source(source_dir, "primary")
    momo_png = resolve_source(source_dir, "momo")
    momo_light_png = resolve_source(source_dir, "momo_light")
    colors_md = source_dir / "strawwu-colors.md"

    if icon_png is None:
        raise SystemExit(f"missing required icon under {source_dir} (strawwu-icon.png or strawwu-logo-icon.png)")

    if primary_png is None:
        primary_png = icon_png
        print(f"note: no wordmark found in {source_dir}; using icon for primary/wordmark assets")

    dest_source = BRAND / "source"
    dest_source.mkdir(parents=True, exist_ok=True)
    for role, resolved in (
        ("icon", icon_png),
        ("primary", primary_png),
        ("momo", momo_png),
        ("momo_light", momo_light_png),
    ):
        if resolved is None:
            continue
        copy_file(resolved, dest_source / canonical_source_name(role, resolved))
    for name in (
        "strawwu-logo-icon.svg",
        "strawwu-logo-primary.svg",
        "strawwu-logo-momo.svg",
        "strawwu-logo-momo-light.svg",
        "strawwu-colors.md",
    ):
        src = source_dir / name
        if src.is_file():
            copy_file(src, dest_source / name)

    # Core branding copies (rounded corners on all raster logos)
    rasterize(icon_png, BRAND / "logo-icon.png", 512)
    rasterize_width(primary_png, BRAND / "logo-wordmark.png", 1200)

    # SVG wrappers (Calamares / web; embedded PNG for fidelity)
    wrap_png_as_svg(icon_png, BRAND / "logo-icon.svg", "StrawWU icon")
    wrap_png_as_svg(icon_png, BRAND / "favicon.svg", "StrawWU favicon", size=64)
    wrap_png_as_svg(primary_png, BRAND / "logo-wordmark.svg", "StrawWU wordmark")
    wrap_png_as_svg(primary_png, BRAND / "logo-wordmark-light.svg", "StrawWU wordmark light")

    mono_light = BRAND / "logo-icon-mono.png"
    mono_dark = BRAND / "logo-icon-mono-dark.png"
    mono_tmp = BRAND / "logo-icon-mono.tmp.png"
    mono_variant(icon_png, mono_tmp, light=True)
    apply_rounded_corners(mono_tmp, mono_light, radius_pct=ICON_CORNER_RADIUS_PCT)
    mono_tmp.unlink(missing_ok=True)
    mono_variant(icon_png, mono_tmp, light=False)
    apply_rounded_corners(mono_tmp, mono_dark, radius_pct=ICON_CORNER_RADIUS_PCT)
    mono_tmp.unlink(missing_ok=True)
    wrap_png_as_svg(mono_light, BRAND / "logo-icon-mono.svg", "StrawWU mono")
    wrap_png_as_svg(mono_dark, BRAND / "logo-icon-mono-dark.svg", "StrawWU mono dark")

    for size in ICON_SIZES:
        rasterize(icon_png, BRAND / f"logo-icon-{size}.png", size)

    # Plymouth + Calamares integration
    plymouth = BRAND / "usr/share/plymouth/themes/strawwu-boot"
    calamares = BRAND / "usr/share/calamares/branding/strawwu"
    plymouth.mkdir(parents=True, exist_ok=True)
    calamares.mkdir(parents=True, exist_ok=True)

    # Plymouth: icon only (title text rendered by theme); no bottom watermark
    rasterize(icon_png, plymouth / "logo.png", 256)
    write_transparent_png(plymouth / "watermark.png")
    rasterize(icon_png, calamares / "strawwu-logo-icon.png", 256)
    wrap_png_as_svg(BRAND / "logo-icon.png", calamares / "strawwu-logo.svg", "StrawWU")
    shutil.copy2(BRAND / "logo-wordmark.png", calamares / "strawwu-logo.png")

    if momo_png is not None:
        rasterize_width(momo_png, BRAND / "logo-momo.png", 1200)
    if momo_light_png is not None:
        rasterize_width(momo_light_png, BRAND / "logo-momo-light.png", 1200)

    sync_downstream_assets()

    preview = build_preview()
    write_text(BRAND / "preview.html", preview)
    write_text(BRAND / "preview-standalone.html", preview)

    readme = f"""# StrawWU Branding Assets (使用者 Logo)

來源目錄：`{source_dir}`

## 檔案

| 檔案 | 用途 |
|------|------|
| `source/strawwu-logo-icon.png` | 主圖標原始檔 |
| `source/strawwu-logo-primary.png` | 橫式字標原始檔 |
| `source/strawwu-logo-momo.png` | Momo 吉祥物（選用） |
| `source/strawwu-logo-momo-light.png` | Momo 淺色版（選用） |
| `logo-icon.svg` / `logo-icon-*.png` | Plymouth / 桌面 / ISO |
| `logo-wordmark.svg` | Calamares / 安裝畫面 |
| `usr/share/plymouth/themes/strawwu-boot/logo.png` | 開機圓角圖標（Title 顯示 StrawWU） |
| `usr/share/plymouth/themes/strawwu-boot/watermark.png` | 透明佔位（不使用底部字標） |

## 色票

| 角色 | HEX |
|------|-----|
| 深色背景 | `{COLORS['bg_deep']}` |
| Linux / Teal | `{COLORS['linux']}` |
| Windows / Amber | `{COLORS['win']}` |
| Straw 金 | `{COLORS['straw']}` |
| Bridge 藍 | `{COLORS['bridge']}` |

重新產生：`python3 ingest_user_logos.py`
"""
    write_text(BRAND / "README.md", readme)

    if colors_md.is_file():
        copy_file(colors_md, BRAND / "source" / "strawwu-colors.md")

    print("ingest complete")


def main() -> None:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    ingest(source)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Ingest user-provided StrawWU logos and generate OS branding assets."""
from __future__ import annotations

import base64
import shutil
import subprocess
import sys
from pathlib import Path

BRAND = Path(__file__).resolve().parent
DEFAULT_SOURCE = Path("/mnt/data/Data/檔案/專案資料/StrawWU")

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


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, capture_output=True)


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    print(f"wrote {path}")


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"copied {src.name} -> {dst}")


def rasterize(src: Path, dst: Path, size: int) -> None:
    run(
        [
            "convert",
            "-background",
            "none",
            str(src),
            "-resize",
            f"{size}x{size}",
            str(dst),
        ]
    )
    print(f"wrote {dst} ({size}px)")


def rasterize_width(src: Path, dst: Path, width: int) -> None:
    run(
        [
            "convert",
            "-background",
            "none",
            str(src),
            "-resize",
            f"{width}x",
            str(dst),
        ]
    )
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
    .preview img {{ max-width: 100%; height: auto; }}
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


def ingest(source_dir: Path) -> None:
    source_dir = source_dir.resolve()
    icon_png = source_dir / "strawwu-logo-icon.png"
    primary_png = source_dir / "strawwu-logo-primary.png"
    momo_png = source_dir / "strawwu-logo-momo.png"
    colors_md = source_dir / "strawwu-colors.md"

    for req in (icon_png, primary_png):
        if not req.is_file():
            raise SystemExit(f"missing required logo: {req}")

    dest_source = BRAND / "source"
    dest_source.mkdir(parents=True, exist_ok=True)
    for name in (
        "strawwu-logo-icon.png",
        "strawwu-logo-icon.svg",
        "strawwu-logo-primary.png",
        "strawwu-logo-primary.svg",
        "strawwu-logo-momo.png",
        "strawwu-logo-momo.svg",
        "strawwu-colors.md",
    ):
        src = source_dir / name
        if src.is_file():
            copy_file(src, dest_source / name)

    # Core branding copies
    shutil.copy2(icon_png, BRAND / "logo-icon.png")
    shutil.copy2(primary_png, BRAND / "logo-wordmark.png")
    print(f"copied icon -> {BRAND / 'logo-icon.png'}")
    print(f"copied primary -> {BRAND / 'logo-wordmark.png'}")

    # SVG wrappers (Calamares / web; embedded PNG for fidelity)
    wrap_png_as_svg(icon_png, BRAND / "logo-icon.svg", "StrawWU icon")
    wrap_png_as_svg(icon_png, BRAND / "favicon.svg", "StrawWU favicon", size=64)
    wrap_png_as_svg(primary_png, BRAND / "logo-wordmark.svg", "StrawWU wordmark")
    wrap_png_as_svg(primary_png, BRAND / "logo-wordmark-light.svg", "StrawWU wordmark light")

    mono_light = BRAND / "logo-icon-mono.png"
    mono_dark = BRAND / "logo-icon-mono-dark.png"
    mono_variant(icon_png, mono_light, light=True)
    mono_variant(icon_png, mono_dark, light=False)
    wrap_png_as_svg(mono_light, BRAND / "logo-icon-mono.svg", "StrawWU mono")
    wrap_png_as_svg(mono_dark, BRAND / "logo-icon-mono-dark.svg", "StrawWU mono dark")

    for size in ICON_SIZES:
        rasterize(icon_png, BRAND / f"logo-icon-{size}.png", size)

    # Plymouth + Calamares integration
    plymouth = BRAND / "usr/share/plymouth/themes/strawwu-boot"
    calamares = BRAND / "usr/share/calamares/branding/strawwu"
    plymouth.mkdir(parents=True, exist_ok=True)
    calamares.mkdir(parents=True, exist_ok=True)

    rasterize(icon_png, plymouth / "logo.png", 256)
    rasterize_width(primary_png, plymouth / "watermark.png", 480)
    wrap_png_as_svg(primary_png, calamares / "strawwu-logo.svg", "StrawWU")
    shutil.copy2(primary_png, calamares / "strawwu-logo.png")

    if momo_png.is_file():
        rasterize_width(momo_png, BRAND / "logo-momo.png", 1200)

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
| `logo-icon.svg` / `logo-icon-*.png` | Plymouth / 桌面 / ISO |
| `logo-wordmark.svg` | Calamares / 安裝畫面 |
| `usr/share/plymouth/themes/strawwu-boot/logo.png` | 開機動畫圖標 |
| `usr/share/plymouth/themes/strawwu-boot/watermark.png` | 開機浮水印字標 |

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

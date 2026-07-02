#!/usr/bin/env python3
"""Generate StrawWU branding assets (Direction A — layered OS stack)."""
from __future__ import annotations

import base64
import subprocess
from pathlib import Path

BRAND = Path(__file__).resolve().parent
COLORS = {
    "bg_deep": "#0a0e14",
    "bg_icon": "#0f1419",
    "bg_surface": "#111820",
    "border": "#243040",
    "linux": "#14b8a6",
    "win": "#f59e0b",
    "straw": "#d4a853",
    "bridge": "#60a5fa",
    "text": "#e8edf5",
    "muted": "#94a3b8",
}


def icon_symbol(cx: float, cy: float, scale: float, *, mono: str | None = None) -> str:
    """Core mark: layered triangle + bridge + dual-runtime base."""
    s = scale
    linux = mono or COLORS["linux"]
    win = mono or COLORS["win"]
    straw = mono or COLORS["straw"]
    bridge = mono or COLORS["bridge"]
    surface = mono or COLORS["bg_surface"]
    border = mono or COLORS["border"]

    # Geometry anchored at (cx, cy) — cy is visual center of mark
    apex_y = cy - 88 * s
    bridge_y = cy + 18 * s
    base_top_y = cy + 58 * s
    base_bot_y = cy + 96 * s
    left_x = cx - 96 * s
    right_x = cx + 96 * s
    mid_x = cx

    parts = [
        # Dual-runtime base (converging platform)
        f'<path d="M {left_x:.1f} {base_top_y:.1f} L {mid_x:.1f} {base_top_y - 22*s:.1f} L {right_x:.1f} {base_top_y:.1f} L {right_x:.1f} {base_bot_y:.1f} L {mid_x:.1f} {base_bot_y - 18*s:.1f} L {left_x:.1f} {base_bot_y:.1f} Z" fill="{surface}" stroke="{border}" stroke-width="{max(1.5, 3*s):.1f}"/>',
        f'<path d="M {left_x:.1f} {base_top_y:.1f} L {mid_x:.1f} {base_top_y - 22*s:.1f} L {mid_x:.1f} {base_bot_y - 18*s:.1f} L {left_x:.1f} {base_bot_y:.1f} Z" fill="{linux}" opacity="0.22"/>',
        f'<path d="M {mid_x:.1f} {base_top_y - 22*s:.1f} L {right_x:.1f} {base_top_y:.1f} L {right_x:.1f} {base_bot_y:.1f} L {mid_x:.1f} {base_bot_y - 18*s:.1f} Z" fill="{win}" opacity="0.22"/>',
        # Linux system layer (triangle roof)
        f'<path d="M {left_x:.1f} {bridge_y:.1f} L {mid_x:.1f} {apex_y:.1f} L {right_x:.1f} {bridge_y:.1f} Z" fill="none" stroke="{linux}" stroke-width="{max(3, 10*s):.1f}" stroke-linejoin="round"/>',
        # Bridge / orchestrator line
        f'<path d="M {left_x + 16*s:.1f} {bridge_y:.1f} L {right_x - 16*s:.1f} {bridge_y:.1f}" stroke="{win}" stroke-width="{max(3, 10*s):.1f}" stroke-linecap="round"/>',
    ]
    if not mono:
        parts.append(
            f'<path d="M {cx - 36*s:.1f} {bridge_y:.1f} L {cx + 36*s:.1f} {bridge_y:.1f}" stroke="{bridge}" stroke-width="{max(2, 5*s):.1f}" stroke-linecap="round" opacity="0.55"/>'
        )
    parts.extend(
        [
            f'<circle cx="{mid_x:.1f}" cy="{bridge_y - 20*s:.1f}" r="{max(4, 12*s):.1f}" fill="{win}"/>',
            f'<circle cx="{mid_x:.1f}" cy="{bridge_y - 20*s:.1f}" r="{max(2, 5*s):.1f}" fill="{straw}"/>',
            f'<circle cx="{mid_x:.1f}" cy="{apex_y + 14*s:.1f}" r="{max(2, 6*s):.1f}" fill="{straw}" opacity="0.85"/>',
        ]
    )
    return "\n  ".join(parts)


def svg_icon(size: int = 512, *, bg: bool = True, mono: str | None = None, bg_color: str = COLORS["bg_icon"]) -> str:
    rx = round(size * 0.22)
    bg_rect = f'<rect width="{size}" height="{size}" rx="{rx}" fill="{bg_color}"/>' if bg else ""
    scale = size / 512
    mark = icon_symbol(size / 2, size / 2 + size * 0.02, scale, mono=mono)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" role="img" aria-label="StrawWU">
  {bg_rect}
  {mark}
</svg>
"""


def svg_favicon() -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" role="img" aria-label="StrawWU">
  <rect width="64" height="64" rx="14" fill="{COLORS['bg_icon']}"/>
  <path d="M12 44 L32 16 L52 44 Z" stroke="{COLORS['linux']}" stroke-width="3" fill="none" stroke-linejoin="round"/>
  <path d="M16 44 L48 44" stroke="{COLORS['win']}" stroke-width="3" stroke-linecap="round"/>
  <path d="M24 44 L40 44" stroke="{COLORS['bridge']}" stroke-width="1.5" stroke-linecap="round" opacity="0.55"/>
  <circle cx="32" cy="36" r="4" fill="{COLORS['win']}"/>
  <circle cx="32" cy="36" r="1.5" fill="{COLORS['straw']}"/>
  <circle cx="32" cy="22" r="1.5" fill="{COLORS['straw']}" opacity="0.85"/>
  <path d="M12 48 L32 42 L52 48 L52 54 L32 50 L12 54 Z" fill="{COLORS['bg_surface']}" stroke="{COLORS['border']}" stroke-width="1"/>
  <path d="M12 48 L32 42 L32 50 L12 54 Z" fill="{COLORS['linux']}" opacity="0.22"/>
  <path d="M32 42 L52 48 L52 54 L32 50 Z" fill="{COLORS['win']}" opacity="0.22"/>
</svg>
"""


def svg_wordmark() -> str:
    icon = icon_symbol(140, 140, 0.55)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 280" role="img" aria-label="StrawWU">
  <rect width="1200" height="280" rx="24" fill="{COLORS['bg_deep']}"/>
  <rect x="40" y="40" width="200" height="200" rx="44" fill="{COLORS['bg_icon']}"/>
  {icon}
  <text x="290" y="152" font-family="'IBM Plex Sans', 'Noto Sans TC', system-ui, sans-serif" font-size="108" font-weight="600" letter-spacing="-1">
    <tspan fill="{COLORS['straw']}">Straw</tspan><tspan fill="{COLORS['text']}">WU</tspan>
  </text>
  <text x="292" y="196" font-family="'IBM Plex Sans', 'Noto Sans TC', system-ui, sans-serif" font-size="26" fill="{COLORS['muted']}" letter-spacing="0.5">Desktop OS · Dual Runtime</text>
  <text x="292" y="228" font-family="'Noto Sans TC', 'IBM Plex Sans', system-ui, sans-serif" font-size="22" fill="{COLORS['linux']}" opacity="0.9">單一桌面，同級調度 Windows 與 Linux 應用</text>
</svg>
"""


def svg_wordmark_light() -> str:
    icon = icon_symbol(140, 140, 0.55, mono="#1e293b")
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 280" role="img" aria-label="StrawWU">
  <rect width="1200" height="280" rx="24" fill="#f4f6f9"/>
  {icon}
  <text x="290" y="152" font-family="'IBM Plex Sans', 'Noto Sans TC', system-ui, sans-serif" font-size="108" font-weight="600" letter-spacing="-1">
    <tspan fill="#b8860b">Straw</tspan><tspan fill="#0f172a">WU</tspan>
  </text>
  <text x="292" y="196" font-family="'IBM Plex Sans', system-ui, sans-serif" font-size="26" fill="#64748b">Desktop OS · Dual Runtime</text>
</svg>
"""


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    print(f"wrote {path}")


def rasterize(svg_path: Path, png_path: Path, size: int) -> None:
    cmd = [
        "convert",
        "-background",
        "none",
        "-density",
        "384",
        str(svg_path),
        "-resize",
        f"{size}x{size}",
        str(png_path),
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    print(f"wrote {png_path} ({size}px)")


def rasterize_wordmark(svg_path: Path, png_path: Path, width: int) -> None:
    cmd = [
        "convert",
        "-background",
        "none",
        "-density",
        "288",
        str(svg_path),
        "-resize",
        f"{width}x",
        str(png_path),
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    print(f"wrote {png_path} ({width}px wide)")


def b64_data_uri(svg_path: Path) -> str:
    data = base64.b64encode(svg_path.read_bytes()).decode("ascii")
    return f"data:image/svg+xml;base64,{data}"


def build_preview() -> str:
  icon_b64 = b64_data_uri(BRAND / "logo-icon.svg")
  fav_b64 = b64_data_uri(BRAND / "favicon.svg")
  word_b64 = b64_data_uri(BRAND / "logo-wordmark.svg")
  mono_b64 = b64_data_uri(BRAND / "logo-icon-mono.svg")
  return f"""<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>StrawWU Branding Preview</title>
  <style>
    :root {{
      --bg: {COLORS['bg_deep']};
      --surface: {COLORS['bg_surface']};
      --border: {COLORS['border']};
      --text: {COLORS['text']};
      --muted: {COLORS['muted']};
      --linux: {COLORS['linux']};
      --win: {COLORS['win']};
      --straw: {COLORS['straw']};
      --bridge: {COLORS['bridge']};
      --light: #f4f6f9;
    }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; font-family: "IBM Plex Sans", "Noto Sans TC", sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }}
    .wrap {{ max-width: 1100px; margin: 0 auto; padding: 32px 20px 64px; }}
    h1 {{ font-size: 1.75rem; font-weight: 600; margin: 0 0 8px; }}
    .sub {{ color: var(--muted); margin-bottom: 28px; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }}
    .card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 20px; }}
    .card h2 {{ margin: 0 0 12px; font-size: 0.95rem; color: var(--muted); font-weight: 500; }}
    .preview {{ display: flex; align-items: center; justify-content: center; min-height: 140px; gap: 16px; flex-wrap: wrap; }}
    .preview img {{ max-width: 100%; height: auto; }}
    .sizes {{ display: flex; align-items: end; gap: 18px; flex-wrap: wrap; }}
    .swatch {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; margin-top: 20px; }}
    .chip {{ border: 1px solid var(--border); border-radius: 8px; padding: 10px; font-size: 0.85rem; }}
    .dot {{ width: 28px; height: 28px; border-radius: 6px; margin-bottom: 6px; border: 1px solid rgba(255,255,255,.08); }}
    .light {{ background: var(--light); color: #0f172a; border-radius: 12px; padding: 20px; margin-top: 16px; }}
    code {{ font-family: "IBM Plex Mono", monospace; font-size: 0.82rem; color: var(--bridge); }}
  </style>
</head>
<body>
  <div class="wrap">
    <h1>StrawWU Logo — Direction A</h1>
    <p class="sub">分層 OS 堆疊：Teal 系統層 · Amber 調度橋 · 雙 runtime 匯流底座 · Straw 金點綴</p>

    <div class="grid">
      <div class="card">
        <h2>主圖標 512px</h2>
        <div class="preview"><img src="{icon_b64}" width="180" alt="icon"/></div>
      </div>
      <div class="card">
        <h2>Favicon 64px</h2>
        <div class="preview"><img src="{fav_b64}" width="64" alt="favicon"/></div>
      </div>
      <div class="card">
        <h2>單色反白</h2>
        <div class="preview" style="background:#0f1419;border-radius:8px"><img src="{mono_b64}" width="96" alt="mono"/></div>
      </div>
    </div>

    <div class="card" style="margin-top:16px">
      <h2>橫式字標</h2>
      <div class="preview"><img src="{word_b64}" style="max-width:100%" alt="wordmark"/></div>
    </div>

    <div class="card" style="margin-top:16px">
      <h2>尺寸可讀性</h2>
      <div class="sizes">
        <div><img src="{fav_b64}" width="16" height="16"/><div style="font-size:.75rem;color:var(--muted)">16</div></div>
        <div><img src="{fav_b64}" width="32" height="32"/><div style="font-size:.75rem;color:var(--muted)">32</div></div>
        <div><img src="{fav_b64}" width="64" height="64"/><div style="font-size:.75rem;color:var(--muted)">64</div></div>
        <div><img src="{icon_b64}" width="128" height="128"/><div style="font-size:.75rem;color:var(--muted)">128</div></div>
        <div><img src="{icon_b64}" width="256" height="256"/><div style="font-size:.75rem;color:var(--muted)">256</div></div>
      </div>
    </div>

    <div class="card" style="margin-top:16px">
      <h2>色票</h2>
      <div class="swatch">
        <div class="chip"><div class="dot" style="background:{COLORS['linux']}"></div>Linux <code>{COLORS['linux']}</code></div>
        <div class="chip"><div class="dot" style="background:{COLORS['win']}"></div>Win32 <code>{COLORS['win']}</code></div>
        <div class="chip"><div class="dot" style="background:{COLORS['straw']}"></div>Straw <code>{COLORS['straw']}</code></div>
        <div class="chip"><div class="dot" style="background:{COLORS['bridge']}"></div>Bridge <code>{COLORS['bridge']}</code></div>
        <div class="chip"><div class="dot" style="background:{COLORS['bg_deep']}"></div>Deep BG <code>{COLORS['bg_deep']}</code></div>
      </div>
    </div>

    <div class="light">
      <strong>設計語意</strong><br/>
      上層 Teal 三角 = Ubuntu/Linux 唯一核心；中層 Amber 橫線 + 節點 = strawwu-runtime 同級調度；底座雙色匯流 = Linux + Win32 共享桌面。無商標仿製、無玻璃擬態。
    </div>
  </div>
</body>
</html>
"""


def main() -> None:
    write_text(BRAND / "logo-icon.svg", svg_icon(512))
    write_text(BRAND / "favicon.svg", svg_favicon())
    write_text(BRAND / "logo-wordmark.svg", svg_wordmark())
    write_text(BRAND / "logo-wordmark-light.svg", svg_wordmark_light())
    write_text(BRAND / "logo-icon-mono.svg", svg_icon(512, mono="#e8edf5"))
    write_text(BRAND / "logo-icon-mono-dark.svg", svg_icon(512, mono="#0f172a", bg_color="#f4f6f9"))

    # OS integration copies
    calamares = BRAND / "usr/share/calamares/branding/strawwu/strawwu-logo.svg"
    write_text(calamares, svg_wordmark())

    for size in (16, 32, 48, 64, 128, 256, 512, 1024):
        out = BRAND / f"logo-icon-{size}.png"
        src = BRAND / ("favicon.svg" if size <= 64 else "logo-icon.svg")
        rasterize(src, out, size)

    rasterize_wordmark(BRAND / "logo-wordmark.svg", BRAND / "logo-wordmark.png", 1200)
    rasterize(BRAND / "logo-icon.svg", BRAND / "logo-icon.png", 512)

    preview = build_preview()
    write_text(BRAND / "preview.html", preview)
    standalone = preview
    write_text(BRAND / "preview-standalone.html", standalone)

    readme = f"""# StrawWU Branding Assets (v2 — Direction A)

延續官網 favicon 的分層三角標，強化為完整 OS 品牌識別。

## 檔案

| 檔案 | 用途 |
|------|------|
| `logo-icon.svg` | 主圖標（512）— Plymouth / 桌面 / ISO |
| `favicon.svg` | Favicon 最佳化（64 viewBox） |
| `logo-wordmark.svg` | 深色橫式字標 |
| `logo-wordmark-light.svg` | 淺色背景字標 |
| `logo-icon-mono.svg` | 單色反白（深色底） |
| `logo-icon-mono-dark.svg` | 單色深色（淺色底） |
| `logo-icon-*.png` | 16–1024 點陣匯出 |

## 色票（與 StrawWUWeb 一致）

| 角色 | HEX |
|------|-----|
| Linux 強調 | `{COLORS['linux']}` |
| Windows 強調 | `{COLORS['win']}` |
| Straw 品牌 | `{COLORS['straw']}` |
| Bridge | `{COLORS['bridge']}` |
| 深色背景 | `{COLORS['bg_deep']}` |
| 圖標底 | `{COLORS['bg_icon']}` |

## 設計語意

- **Teal 三角**：Linux 系統層（唯一核心）
- **Amber 橫線 + 節點**：strawwu-runtime / bridge 調度層
- **雙色底座**：Linux + Win32 同級 runtime 匯流至單一桌面
- **Straw 金點**：StrawCoding 系列識別點綴

禁止：Windows 四格窗、Ubuntu 圓圈、Wine 酒杯、玻璃擬態、光暈。
"""
    write_text(BRAND / "README.md", readme)
    print("done")


if __name__ == "__main__":
    main()

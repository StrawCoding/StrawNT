#!/usr/bin/env python3
"""Render StrawWU official release DoD markdown to HTML (hermes-deliver)."""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CLOSEOUT_DIR = REPO_ROOT / "docs" / "plans" / "official-release"
HTML_DIR = CLOSEOUT_DIR / "html"
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()

CSS = """
:root {
  --bg: #0f1419;
  --surface: #1a2332;
  --text: #e8eef4;
  --muted: #8b9cb3;
  --accent: #14b8a6;
  --border: #2d3a4d;
  --code-bg: #0d1117;
}
* { box-sizing: border-box; }
body {
  font-family: "Segoe UI", system-ui, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.65;
  margin: 0;
  padding: 2rem 1rem 4rem;
}
.wrap { max-width: 56rem; margin: 0 auto; }
header { border-bottom: 1px solid var(--border); margin-bottom: 2rem; padding-bottom: 1rem; }
.brand { color: var(--accent); font-weight: 600; }
h1 { font-size: 1.85rem; margin: 0.5rem 0; }
.meta { color: var(--muted); font-size: 0.9rem; }
h2 { color: var(--accent); font-size: 1.25rem; margin-top: 2rem; border-bottom: 1px solid var(--border); padding-bottom: 0.35rem; }
h3 { font-size: 1.05rem; margin-top: 1.5rem; }
table { width: 100%; border-collapse: collapse; margin: 1rem 0; font-size: 0.92rem; }
th, td { border: 1px solid var(--border); padding: 0.5rem 0.65rem; text-align: left; }
th { background: var(--surface); color: var(--accent); }
code { background: var(--code-bg); border: 1px solid var(--border); border-radius: 4px; padding: 0.1rem 0.35rem; }
pre { background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px; padding: 1rem; overflow-x: auto; }
footer { margin-top: 3rem; color: var(--muted); font-size: 0.85rem; border-top: 1px solid var(--border); padding-top: 1rem; }
"""


def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return text


def md_to_html(md: str) -> str:
    lines = md.splitlines()
    out: list[str] = []
    i = 0
    in_pre = False
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            if in_pre:
                out.append("</code></pre>")
                in_pre = False
            else:
                out.append("<pre><code>")
                in_pre = True
            i += 1
            continue
        if in_pre:
            out.append(html.escape(line))
            i += 1
            continue
        if line.startswith("|") and i + 1 < len(lines) and lines[i + 1].startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip("|").split("|")])
                i += 1
            if len(rows) >= 2:
                out.append("<table>")
                out.append("<tr>" + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr>")
                for row in rows[2:]:
                    out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
                out.append("</table>")
            continue
        if line.startswith("# "):
            out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("## "):
            out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("### "):
            out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.strip():
            out.append(f"<p>{inline(line)}</p>")
        i += 1
    if in_pre:
        out.append("</code></pre>")
    return "\n".join(out)


def main() -> int:
    md_path = CLOSEOUT_DIR / "official-release-dod.md"
    if not md_path.is_file():
        print(f"FAIL: missing {md_path}", file=sys.stderr)
        return 1
    HTML_DIR.mkdir(parents=True, exist_ok=True)
    body = md_to_html(md_path.read_text(encoding="utf-8"))
    doc = f"""<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>StrawWU Official Release 1.0.0 — DoD</title>
  <style>{CSS}</style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="brand">StrawWU Official Release</div>
      <h1>Q9 正式版 1.0.0 — Definition of Done</h1>
      <p class="meta">版本 {html.escape(VERSION)} · official-release · hermes-deliver</p>
    </header>
    <main>
{body}
    </main>
    <footer>
      StrawWU v1.0.0.0 official release · Phase 8/8 · Hermes stage report
    </footer>
  </div>
</body>
</html>
"""
    out_path = HTML_DIR / "official-release-report.html"
    out_path.write_text(doc, encoding="utf-8")
    print(f"PASS: rendered {out_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

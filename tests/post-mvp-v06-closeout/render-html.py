#!/usr/bin/env python3
"""Render StrawWU Post-MVP v0.6 closeout markdown to HTML (hermes-deliver)."""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CLOSEOUT_DIR = REPO_ROOT / "docs" / "plans" / "post-mvp-v06-closeout"
HTML_DIR = CLOSEOUT_DIR / "html"
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()

CSS = """
:root {
  --bg: #0f1419;
  --surface: #1a2332;
  --text: #e8eef4;
  --muted: #8b9cb3;
  --accent: #14b8a6;
  --accent-dim: #0d9488;
  --border: #2d3a4d;
  --code-bg: #0d1117;
  --pass: #34d399;
}
* { box-sizing: border-box; }
body {
  font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.65;
  margin: 0;
  padding: 2rem 1rem 4rem;
}
.wrap { max-width: 56rem; margin: 0 auto; }
header {
  border-bottom: 1px solid var(--border);
  margin-bottom: 2rem;
  padding-bottom: 1rem;
}
.brand { color: var(--accent); font-weight: 600; letter-spacing: 0.02em; }
h1 { color: var(--text); font-size: 1.85rem; margin: 0.5rem 0 0.25rem; }
.meta { color: var(--muted); font-size: 0.9rem; }
h2 {
  color: var(--accent);
  font-size: 1.25rem;
  margin-top: 2rem;
  border-bottom: 1px solid var(--border);
  padding-bottom: 0.35rem;
}
h3 { color: var(--text); font-size: 1.05rem; margin-top: 1.5rem; }
p { margin: 0.75rem 0; }
a { color: var(--accent); }
ul, ol { padding-left: 1.4rem; }
li { margin: 0.35rem 0; }
table {
  width: 100%;
  border-collapse: collapse;
  margin: 1rem 0;
  font-size: 0.92rem;
}
th, td {
  border: 1px solid var(--border);
  padding: 0.5rem 0.65rem;
  text-align: left;
}
th { background: var(--surface); color: var(--accent); }
tr:nth-child(even) td { background: rgba(26, 35, 50, 0.5); }
code {
  background: var(--code-bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 0.1rem 0.35rem;
  font-size: 0.88em;
}
pre {
  background: var(--code-bg);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 1rem;
  overflow-x: auto;
  font-size: 0.85rem;
}
pre code { border: none; padding: 0; background: transparent; }
blockquote {
  border-left: 3px solid var(--accent);
  margin: 1rem 0;
  padding: 0.25rem 1rem;
  color: var(--muted);
}
footer {
  margin-top: 3rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border);
  color: var(--muted);
  font-size: 0.85rem;
}
"""


def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r'<code>\1</code>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def md_to_html(md: str) -> str:
    lines = md.splitlines()
    out: list[str] = []
    i = 0
    in_pre = False
    in_table = False
    table_rows: list[str] = []

    def flush_table() -> None:
        nonlocal in_table, table_rows
        if not table_rows:
            return
        out.append("<table>")
        for ri, row in enumerate(table_rows):
            cells = [c.strip() for c in row.strip("|").split("|")]
            tag = "th" if ri == 0 else "td"
            out.append("<tr>" + "".join(f"<{tag}>{inline(c)}</{tag}>" for c in cells) + "</tr>")
        out.append("</table>")
        table_rows = []
        in_table = False

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
        if "|" in line and line.strip().startswith("|"):
            if not in_table:
                in_table = True
            table_rows.append(line)
            i += 1
            continue
        elif in_table:
            flush_table()
        if line.startswith("# "):
            out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("## "):
            out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("### "):
            out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.startswith("> "):
            out.append(f"<blockquote><p>{inline(line[2:])}</p></blockquote>")
        elif re.match(r"^[-*] ", line):
            items = [line]
            i += 1
            while i < len(lines) and re.match(r"^[-*] ", lines[i]):
                items.append(lines[i])
                i += 1
            out.append("<ul>")
            for it in items:
                out.append(f"<li>{inline(it[2:])}</li>")
            out.append("</ul>")
            continue
        elif line.strip() == "":
            pass
        else:
            out.append(f"<p>{inline(line)}</p>")
        i += 1
    if in_table:
        flush_table()
    if in_pre:
        out.append("</code></pre>")
    return "\n".join(out)


def render_report(md_path: Path) -> str:
    body = md_to_html(md_path.read_text(encoding="utf-8"))
    return f"""<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>StrawWU Post-MVP v0.6 Closeout — Definition of Done</title>
  <style>{CSS}</style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="brand">StrawWU Post-MVP v0.6 Closeout</div>
      <h1>驅動與硬體 — v0.6 DoD 驗收</h1>
      <p class="meta">版本 {html.escape(VERSION)} · post-v06-closeout · hermes-deliver</p>
    </header>
    <main>
{body}
    </main>
    <footer>
      StrawWU v0.6 drivers/HW · 10 Post-MVP stages · Next → post-upg-rollback
    </footer>
  </div>
</body>
</html>
"""


def main() -> int:
    md_path = CLOSEOUT_DIR / "post-mvp-v06-dod.md"
    if not md_path.is_file():
        print(f"FAIL: missing {md_path}", file=sys.stderr)
        return 1
    HTML_DIR.mkdir(parents=True, exist_ok=True)
    out_path = HTML_DIR / "post-mvp-v06-closeout-report.html"
    out_path.write_text(render_report(md_path), encoding="utf-8")
    print(f"PASS: rendered {out_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

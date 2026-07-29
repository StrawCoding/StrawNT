#!/usr/bin/env python3
"""Render Native PE pe7 closeout markdown to HTML (hermes-deliver)."""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CLOSEOUT_DIR = REPO_ROOT / "docs" / "plans" / "portable-core"
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
  --pass: #34d399;
  --partial: #fbbf24;
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
.badge-pass { color: var(--pass); font-weight: 600; }
.badge-partial { color: var(--partial); font-weight: 600; }
"""


def md_to_html(md: str) -> str:
    lines = md.splitlines()
    out: list[str] = []
    in_code = False
    in_ul = False
    in_ol = False
    in_table = False
    table_rows: list[str] = []

    def close_lists() -> None:
        nonlocal in_ul, in_ol
        if in_ul:
            out.append("</ul>")
            in_ul = False
        if in_ol:
            out.append("</ol>")
            in_ol = False

    def flush_table() -> None:
        nonlocal in_table, table_rows
        if not table_rows:
            return
        out.append("<table>")
        for i, row in enumerate(table_rows):
            cells = [c.strip() for c in row.strip("|").split("|")]
            tag = "th" if i == 0 else "td"
            if i == 1 and all(re.match(r"^:?-+:?$", c) for c in cells):
                continue
            out.append("<tr>" + "".join(f"<{tag}>{inline(c)}</{tag}>" for c in cells) + "</tr>")
        out.append("</table>")
        table_rows = []
        in_table = False

    def inline(text: str) -> str:
        text = html.escape(text)
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
        return text

    for line in lines:
        if line.startswith("```"):
            close_lists()
            flush_table()
            if in_code:
                out.append("</code></pre>")
                in_code = False
            else:
                out.append("<pre><code>")
                in_code = True
            continue
        if in_code:
            out.append(html.escape(line))
            continue
        if line.strip().startswith("|"):
            close_lists()
            in_table = True
            table_rows.append(line)
            continue
        if in_table:
            flush_table()
        if not line.strip():
            close_lists()
            continue
        if line.startswith("# "):
            close_lists()
            out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("## "):
            close_lists()
            out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("### "):
            close_lists()
            out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.startswith("> "):
            close_lists()
            out.append(f"<blockquote><p>{inline(line[2:])}</p></blockquote>")
        elif re.match(r"^- ", line):
            if in_ol:
                out.append("</ol>")
                in_ol = False
            if not in_ul:
                out.append("<ul>")
                in_ul = True
            out.append(f"<li>{inline(line[2:])}</li>")
        elif re.match(r"^\d+\. ", line):
            if in_ul:
                out.append("</ul>")
                in_ul = False
            if not in_ol:
                out.append("<ol>")
                in_ol = True
            item = re.sub(r"^\d+\. ", "", line)
            out.append(f"<li>{inline(item)}</li>")
        else:
            close_lists()
            out.append(f"<p>{inline(line)}</p>")

    close_lists()
    flush_table()
    if in_code:
        out.append("</code></pre>")
    return "\n".join(out)


def main() -> int:
    md_path = CLOSEOUT_DIR / "pe-closeout-report.md"
    if not md_path.is_file():
        print(f"missing {md_path}", file=sys.stderr)
        return 1
    body = md_to_html(md_path.read_text(encoding="utf-8"))
    HTML_DIR.mkdir(parents=True, exist_ok=True)
    out_path = HTML_DIR / "pe-closeout-report.html"
    doc = f"""<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>StrawWU Portable Native PE Closeout</title>
  <style>{CSS}</style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="brand">StrawWU</div>
      <h1>Native PE Real Exec Closeout</h1>
      <p class="meta">版本 {html.escape(VERSION)} · pe7-closeout · hermes-deliver</p>
    </header>
    {body}
    <footer>StrawWU Portable · native PE / strawwu-nt · generated from pe-closeout-report.md</footer>
  </div>
</body>
</html>
"""
    out_path.write_text(doc, encoding="utf-8")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

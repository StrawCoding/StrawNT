#!/usr/bin/env python3
"""Render StrawWU user markdown guides to self-contained HTML (hermes-deliver)."""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
USER_DOCS = REPO_ROOT / "docs" / "user"
HTML_DIR = USER_DOCS / "html"
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
.wrap { max-width: 52rem; margin: 0 auto; }
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
pre code { border: none; padding: 0; background: none; }
blockquote {
  border-left: 3px solid var(--accent);
  margin: 1rem 0;
  padding: 0.25rem 0 0.25rem 1rem;
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

    def inline(text: str) -> str:
        text = html.escape(text)
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
        return text

    while i < len(lines):
        line = lines[i]

        if line.strip().startswith("```"):
            if in_pre:
                out.append("</code></pre>")
                in_pre = False
            else:
                flush_table()
                out.append("<pre><code>")
                in_pre = True
            i += 1
            continue

        if in_pre:
            out.append(html.escape(line) + "\n")
            i += 1
            continue

        if "|" in line and line.strip().startswith("|"):
            if re.match(r"^\|[\s\-:|]+\|$", line.strip()):
                i += 1
                continue
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
        elif re.match(r"^\d+\. ", line):
            items = [line]
            i += 1
            while i < len(lines) and re.match(r"^\d+\. ", lines[i]):
                items.append(lines[i])
                i += 1
            out.append("<ol>")
            for it in items:
                item_text = re.sub(r"^\d+\.\s*", "", it)
                out.append(f"<li>{inline(item_text)}</li>")
            out.append("</ol>")
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


def render_guide(md_path: Path, title_suffix: str) -> str:
    body = md_to_html(md_path.read_text(encoding="utf-8"))
    return f"""<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>StrawWU — {html.escape(title_suffix)}</title>
  <style>{CSS}</style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="brand">StrawWU User Docs</div>
      <h1>{html.escape(title_suffix)}</h1>
      <p class="meta">版本 {html.escape(VERSION)} · DOC1 · hermes-deliver</p>
    </header>
    <main>
{body}
    </main>
    <footer>
      StrawWU v0.5 預發布使用者文件 · 支援渠道 TBD · 問題回報：strawwu-bug-report-gtk
    </footer>
  </div>
</body>
</html>
"""


GUIDES = [
    ("install-guide.md", "install-guide.html", "安裝與首次設定指南"),
    ("rescue-guide.md", "rescue-guide.html", "救援與修復指南"),
]


def _atomic_write(path: Path, content: str) -> None:
    """Write via temp file + rename to avoid parallel preflight read races."""
    import os
    import tempfile

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
        text=True,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main() -> int:
    HTML_DIR.mkdir(parents=True, exist_ok=True)
    for md_name, html_name, title in GUIDES:
        md_path = USER_DOCS / md_name
        if not md_path.is_file():
            print(f"FAIL: missing {md_path}", file=sys.stderr)
            return 1
        out_path = HTML_DIR / html_name
        _atomic_write(out_path, render_guide(md_path, title))
        print(f"PASS: rendered {out_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

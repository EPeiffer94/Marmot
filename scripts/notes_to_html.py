#!/usr/bin/env python3
"""Turn release-notes Markdown into the small HTML Sparkle shows in the
in-app update window. Handles what our notes use: paragraphs, "- " bullets,
**bold**, `code`, [links](https://...), and "#"/"**Heading**" lines.

Usage: python3 scripts/notes_to_html.py notes.md
"""
import html
import re
import sys


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    text = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', text)
    return text


def convert(markdown):
    out, in_list = [], False
    for raw in markdown.splitlines():
        line = raw.strip()
        if line.startswith("<!--"):
            continue
        bullet = re.match(r"^[-*]\s+(.*)", line)
        if bullet:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(bullet.group(1))}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if not line:
            continue
        heading = re.match(r"^#{1,6}\s+(.*)", line)
        if heading:
            out.append(f"<h3>{inline(heading.group(1))}</h3>")
        elif re.fullmatch(r"\*\*[^*]+\*\*", line):
            out.append(f"<h3>{inline(line[2:-2])}</h3>")
        else:
            out.append(f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    # "]]>" would end the CDATA block the HTML is wrapped in.
    return "\n".join(out).replace("]]>", "]]&gt;")


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        print(convert(f.read()))

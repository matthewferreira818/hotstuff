"""Builds the /notes/ section — the written record of how this store and
East Coast Social actually work.

Why it exists: the storefront rotates every three days and cannot rank on
its own (see make_category_pages.py). Notes are the opposite kind of page —
one URL, one topic, written once, true indefinitely. They are also the one
thing a content farm cannot copy, because they are first-hand.

Source of truth is content/notes/*.md. Each file starts with a small
front-matter block, then the body in a deliberately narrow slice of
Markdown (headings, lists, code fences, blockquotes, links, bold, italic).
No Markdown library: pip loses packages between containers here, and a
stdlib renderer can't surprise us with different HTML on a different day.

    title:       page title / <h1>
    description: meta description + the line shown on the index
    date:        YYYY-MM-DD, published date
    draft:       true keeps it out of the build entirely (nothing written,
                 nothing linked, nothing in the sitemap)
    ---          end of front matter

Every claim in these pages has to be true today. When one stops being
true, the page changes the same day — that is the whole reason the source
lives in the repo next to the code it describes.

    python make_notes.py
"""

import html
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "content" / "notes"
OUT = HERE / "notes"
SITE = "https://findhotstuff.com"
AUTHOR = "Matthew Ferreira"

CSS = """
  :root { --bg:#12090d; --card:#1d1116; --ink:#f6eef1; --muted:#b9a4ac;
          --line:rgba(246,238,241,.14); --amber:#ffa62b; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink); line-height:1.7;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  a { color:var(--amber); }
  .wrap { max-width:720px; margin:0 auto; padding:0 20px; }
  header.bar { border-bottom:1px solid var(--line); padding:14px 0; }
  header.bar a { color:var(--ink); text-decoration:none; font-weight:700; }
  h1 { font-size:clamp(1.7rem,5vw,2.4rem); line-height:1.25; margin:30px 0 10px; }
  h2 { font-size:1.25rem; margin:36px 0 10px; }
  h3 { font-size:1.05rem; margin:28px 0 8px; color:var(--amber); }
  .meta { color:var(--muted); font-size:.9rem; margin:0 0 28px; }
  .lede { color:var(--muted); }
  article p, article li { color:#e7dade; }
  blockquote { margin:22px 0; padding:2px 0 2px 16px; border-left:3px solid var(--amber);
               color:var(--muted); }
  code { background:var(--card); border:1px solid var(--line); border-radius:5px;
         padding:1px 5px; font-size:.9em; }
  pre { background:var(--card); border:1px solid var(--line); border-radius:12px;
        padding:14px 16px; overflow-x:auto; }
  pre code { background:none; border:0; padding:0; }
  table { border-collapse:collapse; width:100%; margin:22px 0; font-size:.94rem; }
  th, td { border:1px solid var(--line); padding:8px 10px; text-align:left; }
  th { color:var(--amber); }
  hr { border:0; border-top:1px solid var(--line); margin:34px 0; }
  ul.notes { list-style:none; padding:0; }
  ul.notes li { border-bottom:1px solid var(--line); padding:18px 0; }
  ul.notes a { font-weight:700; font-size:1.06rem; text-decoration:none; }
  ul.notes p { margin:6px 0 0; color:var(--muted); font-size:.95rem; }
  ul.notes .when { display:block; color:var(--muted); font-size:.82rem; margin-bottom:4px; }
  footer { color:var(--muted); font-size:.86rem; border-top:1px solid var(--line);
           margin-top:44px; padding:20px 0 46px; }
"""

GC = ('<script data-goatcounter="https://theycallmemattyb.goatcounter.com/count"'
      ' async src="//gc.zgo.at/count.js"></script>')


# --- the narrow Markdown slice -----------------------------------------

def inline(text):
    """Escape first, then re-introduce only the marks we allow. Doing it in
    this order means note text can contain < and & safely."""
    out = html.escape(text)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", out)
    return out


def render_body(md):
    lines = md.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]

        if line.startswith("```"):                      # fenced code
            i += 1
            buf = []
            while i < len(lines) and not lines[i].startswith("```"):
                buf.append(lines[i]); i += 1
            i += 1
            out.append("<pre><code>" + html.escape("\n".join(buf)) + "</code></pre>")
            continue

        if re.match(r"^#{1,3} ", line):                 # headings
            level = len(line) - len(line.lstrip("#"))
            out.append(f"<h{level}>{inline(line[level:].strip())}</h{level}>")
            i += 1
            continue

        if line.strip() == "---":                       # rule
            out.append("<hr>"); i += 1
            continue

        if line.startswith("|"):                        # table
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append(lines[i]); i += 1
            cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
            cells = [c for c in cells if not all(set(x) <= set("-: ") for x in c)]
            head = "".join(f"<th>{inline(c)}</th>" for c in cells[0])
            body = "".join(
                "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>"
                for row in cells[1:])
            out.append(f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>")
            continue

        if re.match(r"^\s*[-*] |^\s*\d+\. ", line):      # lists
            ordered = bool(re.match(r"^\s*\d+\. ", line))
            items = []
            while i < len(lines) and re.match(r"^\s*[-*] |^\s*\d+\. ", lines[i]):
                items.append(re.sub(r"^\s*(?:[-*]|\d+\.) ", "", lines[i])); i += 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(t)}</li>" for t in items) + f"</{tag}>")
            continue

        if line.startswith("> "):                       # blockquote
            buf = []
            while i < len(lines) and lines[i].startswith("> "):
                buf.append(lines[i][2:]); i += 1
            out.append("<blockquote>" + inline(" ".join(buf)) + "</blockquote>")
            continue

        if not line.strip():                            # blank
            i += 1
            continue

        buf = []                                        # paragraph
        while i < len(lines) and lines[i].strip() and not re.match(
                r"^(#{1,3} |```|\||> |\s*[-*] |\s*\d+\. |---$)", lines[i]):
            buf.append(lines[i]); i += 1
        out.append("<p>" + inline(" ".join(buf)) + "</p>")

    return "\n".join(out)


# --- front matter ------------------------------------------------------

def parse(path):
    raw = path.read_text(encoding="utf-8")
    head, _, body = raw.partition("\n---\n")
    meta = {}
    for line in head.split("\n"):
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
    meta["slug"] = path.stem
    meta["body"] = body.strip()
    meta["draft"] = meta.get("draft", "").lower() == "true"
    for required in ("title", "description", "date"):
        if not meta.get(required):
            raise SystemExit(f"{path.name}: missing '{required}' in front matter")
    return meta


# --- pages -------------------------------------------------------------

def shell(title, desc, url, inner, extra_ld=""):
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc[:158])}">
<link rel="canonical" href="{url}">
<meta property="og:type" content="article">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(desc[:158])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}/assets/og-card.png">
{extra_ld}
<style>{CSS}</style>
</head>
<body>
<header class="bar"><div class="wrap"><a href="{SITE}/">← HotsTuff</a></div></header>
{inner}
{GC}
</body>
</html>
"""


def render_note(meta, others):
    url = f"{SITE}/notes/{meta['slug']}/"
    ld = ('<script type="application/ld+json">\n'
          + json.dumps({"@context": "https://schema.org", "@type": "Article",
                        "headline": meta["title"], "description": meta["description"],
                        "datePublished": meta["date"], "url": url,
                        "author": {"@type": "Person", "name": AUTHOR},
                        "publisher": {"@type": "Organization", "name": "HotsTuff",
                                      "url": SITE}})
          + "\n</script>")
    more = "".join(
        f'<li><a href="{SITE}/notes/{o["slug"]}/">{html.escape(o["title"])}</a></li>'
        for o in others if o["slug"] != meta["slug"])
    more_block = (f"<h2>More notes</h2><ul>{more}</ul>" if more else "")
    inner = f"""<main class="wrap">
<article>
  <h1>{html.escape(meta['title'])}</h1>
  <p class="meta">{meta['date']} · {html.escape(AUTHOR)}</p>
{render_body(meta['body'])}
</article>
{more_block}
</main>
<footer class="wrap">
  Written from the actual build. If something here stops being true, the page
  changes — <a href="{SITE}/build/">how the whole thing works</a> ·
  <a href="{SITE}/notes/">all notes</a> · <a href="{SITE}/">the shop</a>
</footer>"""
    return shell(f"{meta['title']} · HotsTuff", meta["description"], url, inner, ld)


def render_index(notes):
    rows = "\n".join(
        f'    <li><span class="when">{n["date"]}</span>'
        f'<a href="{SITE}/notes/{n["slug"]}/">{html.escape(n["title"])}</a>'
        f'<p>{html.escape(n["description"])}</p></li>' for n in notes)
    inner = f"""<main class="wrap">
  <h1>Notes</h1>
  <p class="lede">Working notes from building and running an automated
     storefront and a social-posting service around a full-time job. Written
     from what actually happened — including the parts that broke. Nothing
     here is theory; if a claim stops being true, the page gets changed.</p>
  <ul class="notes">
{rows}
  </ul>
</main>
<footer class="wrap">
  <a href="{SITE}/build/">How the whole system works</a> ·
  <a href="{SITE}/">the shop</a> · <a href="{SITE}/automation/">the service</a>
</footer>"""
    return shell("Notes · HotsTuff",
                 "Working notes from building an automated storefront and a "
                 "social-posting service around a full-time job.",
                 f"{SITE}/notes/", inner)


def main():
    SRC.mkdir(parents=True, exist_ok=True)
    notes = [parse(p) for p in sorted(SRC.glob("*.md"))]
    live = sorted((n for n in notes if not n["draft"]),
                  key=lambda n: n["date"], reverse=True)
    drafts = [n for n in notes if n["draft"]]

    OUT.mkdir(parents=True, exist_ok=True)
    for n in live:
        d = OUT / n["slug"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.html").write_text(render_note(n, live), encoding="utf-8")
        print(f"  /notes/{n['slug']}/")
    (OUT / "index.html").write_text(render_index(live), encoding="utf-8")
    print(f"  /notes/  index with {len(live)} note(s)"
          + (f", {len(drafts)} draft(s) held back" if drafts else ""))

    # keep sitemap.xml correct without a second source of truth
    import make_category_pages
    print(f"  sitemap.xml  {make_category_pages.write_sitemap(HERE / 'sitemap.xml')} URLs")


if __name__ == "__main__":
    main()

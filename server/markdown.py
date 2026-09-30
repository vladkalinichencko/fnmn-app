"""The Markdown every package carries: math in `$`/`$$`, and a blank line only where a paragraph ends.

The app draws each blank-line block as one paragraph, so a display formula that sits inside a
sentence must stay attached to the text around it by single newlines.
"""

from __future__ import annotations

import re

SENTENCE_END = re.compile(r"[.!?»\")\]]\s*$")
CONTINUATION = re.compile(r"^(?:[a-zа-яё,;.)]|(?:where|which|with|and|or|so|then|for|in|is|are|since|because|that)\b)")


SITE_HEADER = re.compile(r"\A\s*#{1,6} \[[^\]]+\]\([^)]*\)[ \t]*\n+")
BYLINE = re.compile(r"\A((?:\s*#{1,6} .+\n+|\s*!\[[^\]]*\]\([^)]*\)\n+)*)\s*[*_]?By [^\n]{1,60}?[*_]?\n\n", re.I)


def normalize(markdown: str) -> str:
    return join_display_math(tex_delimiters(without_page_chrome(markdown)))


def without_page_chrome(markdown: str) -> str:
    """Drops what the page wraps around the article: a first heading that only links to the site's home,
    and a short "By …" line before the text. Neither is part of what the reader came for."""
    markdown = SITE_HEADER.sub("", markdown, count=1)
    return BYLINE.sub(r"\1", markdown, count=1)


def had_site_header(markdown: str) -> bool:
    return SITE_HEADER.match(markdown) is not None


def plain_title(heading: str) -> str:
    """A heading as a title: links keep their text, emphasis and code marks go."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    return re.sub(r"[*_`]", "", text).strip()


def page_title(title: str) -> str:
    """A browser tab title without the site name it ends with: "Article – vfxblog" becomes "Article"."""
    return re.sub(r"\s+[–—|·-]\s+[^–—|·]{1,30}$", "", title).strip() or title


def first_heading(markdown: str) -> str | None:
    return next((plain_title(line[2:]) for line in markdown.splitlines() if line.startswith("# ")), None)


def tex_delimiters(markdown: str) -> str:
    """Turns `\\[ … \\]` into `$$ … $$` and `\\( … \\)` into `$ … $`, leaving code and existing `$` math untouched.
    A line break `\\\\[4pt]` inside LaTeX is not an opening bracket."""
    pieces = re.split(r"(```.*?```|`[^`\n]*`|\$\$.*?\$\$|(?<!\\)\$[^$\n]+?\$)", markdown, flags=re.S)
    for index in range(0, len(pieces), 2):
        piece = re.sub(r"(?<!\\)\\\[(.+?)(?<!\\)\\\]", lambda m: f"$${m.group(1)}$$", pieces[index], flags=re.S)
        pieces[index] = re.sub(r"(?<!\\)\\\((.+?)(?<!\\)\\\)", lambda m: f"${m.group(1).strip()}$", piece, flags=re.S)
    return "".join(pieces)


def join_display_math(markdown: str) -> str:
    """Glues a `$$` block to the paragraph before and after it when the sentence runs through it."""
    blocks = re.split(r"\n[ \t]*\n", markdown)
    merged: list[str] = []
    glue_next = False
    for block in blocks:
        stripped = block.strip()
        is_math = stripped.startswith("$$") and stripped.endswith("$$") and len(stripped) > 4
        if is_math and merged and _runs_on(merged[-1]):
            merged[-1] = merged[-1].rstrip() + "\n" + stripped
            glue_next = True
            continue
        if glue_next and stripped and CONTINUATION.match(stripped):
            merged[-1] = merged[-1] + "\n" + stripped
        else:
            merged.append(block)
        glue_next = False
    return "\n\n".join(merged)


def _runs_on(paragraph: str) -> bool:
    last = paragraph.rstrip()
    if not last or last.lstrip().startswith(("#", "```", "|", ">", "!")):
        return False
    return not SENTENCE_END.search(last)

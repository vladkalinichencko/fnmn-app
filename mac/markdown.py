"""The Markdown every package carries: math in `$`/`$$`, and a blank line only where a paragraph ends.

The app draws each blank-line block as one paragraph, so a display formula that sits inside a
sentence must stay attached to the text around it by single newlines.
"""

from __future__ import annotations

import re

SENTENCE_END = re.compile(r"[.!?»\")\]]\s*$")
CONTINUATION = re.compile(r"^(?:[a-zа-яё,;.)]|(?:where|which|with|and|or|so|then|for|in|is|are|since|because|that)\b)")


def normalize(markdown: str) -> str:
    return join_display_math(tex_delimiters(markdown))


def plain_title(heading: str) -> str:
    """A heading as a title: links keep their text, emphasis and code marks go."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    return re.sub(r"[*_`]", "", text).strip()


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

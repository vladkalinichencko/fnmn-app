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


HEADING = re.compile(r"^(#{1,6}) (.+)$", re.M)
LONG_HEADING = 200
CODE = re.compile(r"(```.*?```)", re.S)
INLINE_CODE_OR_MATH = re.compile(r"(?<!`)(`+)(?!`).+?(?<!`)\1(?!`)|\$\$.*?\$\$|(?<!\\)\$[^$\n]+?\$", re.S)
BOLD = re.compile(r"(?<!\*)\*\*(?!\*)")
STARS = re.compile(r"\*{3,}")
JOINED_BOLD = re.compile(r"([^\s*])\*{4}(?=[^\s*])")
OPENING_PUNCTUATION = "«„“‘([{—–-"
CLOSING_PUNCTUATION = "»”’)]}.,:;!?…"


RULE = re.compile(r"[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*")


def normalize(markdown: str) -> str:
    return join_display_math(
        tex_delimiters(_outside_code(without_page_chrome(markdown), lambda text: bold_runs(headings(without_rules(text)))))
    )


def without_rules(markdown: str) -> str:
    """A horizontal rule would be a paragraph of its own, a plate with a line on it, so it goes. A `---` right under
    a line of text is that line's heading mark and stays."""

    lines = markdown.split("\n")
    kept = [line for index, line in enumerate(lines) if not (RULE.fullmatch(line) and (index == 0 or not lines[index - 1].strip()))]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(kept))


def _outside_code(markdown: str, change) -> str:
    pieces = CODE.split(markdown)
    return "".join(piece if index % 2 else change(piece) for index, piece in enumerate(pieces))


def headings(markdown: str) -> str:
    """A heading is bold already, so bold marks inside it go. One as long as a paragraph is a paragraph:
    sites set a lead in `<h4>` for its size."""

    def plain(match: re.Match) -> str:
        text = match.group(2).replace("**", "")
        text = re.sub(r"\s{2,}", " ", text).strip()
        return text if len(plain_title(text)) > LONG_HEADING else f"{match.group(1)} {text}"

    return HEADING.sub(plain, markdown)


def bold_runs(markdown: str) -> str:
    """Repairs `**` the way HTML leaves it: `**a****b**` from two `<b>` in a row becomes one run, and a run gets
    its space back where Markdown would not read its marks, as in `**Eyes:**green`, or where it follows a link."""
    return "\n\n".join(_spaced_bold(paragraph) for paragraph in re.split(r"\n[ \t]*\n", markdown))


def _spaced_bold(paragraph: str) -> str:
    """A paragraph with any other run of three or more stars is left as it came: `****X****` may be a `<b>` inside
    a `<b>` or two empty ones, and its marks cannot be paired."""
    if any(not _joins_bold(paragraph, run) for run in STARS.finditer(paragraph)):
        return paragraph
    paragraph = JOINED_BOLD.sub(
        lambda m: m.group(1) + ("" if m.group(1) in "«„“‘([{" or paragraph[m.end()] in CLOSING_PUNCTUATION else " "),
        paragraph,
    )
    marks = _bold_marks(paragraph)
    if len(marks) % 2:
        return paragraph
    empty = [(marks[k], marks[k + 1]) for k in range(0, len(marks), 2) if not paragraph[marks[k] + 2 : marks[k + 1]].strip()]
    for start, end in reversed(empty):
        paragraph = paragraph[:start] + paragraph[start + 2 : end] + paragraph[end + 2 :]
    marks = _bold_marks(paragraph)
    for k in reversed(range(len(marks))):
        i = marks[k]
        before = paragraph[i - 1] if i > 0 else " "
        after = paragraph[i + 2] if i + 2 < len(paragraph) else " "
        if k % 2 == 0:
            if (before.isalnum() and punctuation(after) and after not in CLOSING_PUNCTUATION) or (
                before in ")]" and (after.isalnum() or after in "«—–")
            ):
                paragraph = paragraph[:i] + " " + paragraph[i:]
        elif punctuation(before) and before not in OPENING_PUNCTUATION and after.isalnum():
            paragraph = paragraph[: i + 2] + " " + paragraph[i + 2 :]
    return paragraph


def _joins_bold(paragraph: str, run: re.Match) -> bool:
    """`****` between two characters inside a bold run: one `<b>` closing right where the next opens."""
    start, end = run.span()
    if end - start != 4 or start == 0 or end == len(paragraph) or paragraph[start - 1].isspace() or paragraph[end].isspace():
        return False
    marks = len([i for i in _bold_marks(paragraph) if i < start]) + 2 * len([r for r in STARS.finditer(paragraph, 0, start)])
    return marks % 2 == 1


def punctuation(character: str) -> bool:
    return not character.isalnum() and not character.isspace()


def _bold_marks(paragraph: str) -> list[int]:
    """Every `**` outside code and math that can open or close a run: one with spaces on both sides is text."""
    spans = [match.span() for match in INLINE_CODE_OR_MATH.finditer(paragraph)]
    return [
        match.start()
        for match in BOLD.finditer(paragraph)
        if not any(a <= match.start() < b for a, b in spans)
        and not ((paragraph[match.start() - 1] if match.start() else " ").isspace() and (paragraph[match.end()] if match.end() < len(paragraph) else " ").isspace())
    ]



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
    A line break `\\\\[4pt]` inside LaTeX is not an opening bracket. A `$…$` written inside the brackets, as in
    `\\text{for $x$}`, would end the formula early, so its dollars go and the text stays."""
    pieces = re.split(r"(```.*?```|`[^`\n]*`|\$\$.*?\$\$)", markdown, flags=re.S)
    for index in range(0, len(pieces), 2):
        piece = re.sub(r"(?<!\\)\\\[(.+?)(?<!\\)\\\]", lambda m: f"$${_without_dollars(m.group(1))}$$", pieces[index], flags=re.S)
        pieces[index] = re.sub(r"(?<!\\)\\\((.+?)(?<!\\)\\\)", lambda m: f"${_without_dollars(m.group(1)).strip()}$", piece, flags=re.S)
    return "".join(pieces)


def _without_dollars(formula: str) -> str:
    return re.sub(r"(?<!\\)\$", "", formula)


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

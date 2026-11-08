"""A web page's article as the Markdown a package carries: `page_article` finds the article in the page's tree, and
this module writes it, block by block and inline piece by inline piece, with the pictures and videos it names."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin, urlparse

from lxml import html

from adapters.page_article import (
    NEGATIVE,
    article_root,
    block,
    contains_prose,
    holds_templates,
    live_figure,
    main_content,
    math_source,
    selector,
    widget,
)
from markdown import CLOSING_PUNCTUATION, OPENING_PUNCTUATION, punctuation
from package import asset_path

_ASSET_EXTENSIONS = {".gif", ".png", ".jpg", ".jpeg", ".webp", ".svg", ".mp4", ".webm", ".mov"}


def article_markdown(source: str, page_url: str) -> tuple[str, dict[str, str]]:
    document = html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))
    document.make_links_absolute(page_url, resolve_base_href=True, handle_failures="ignore")
    downloads: dict[str, str] = {}
    if found := main_content(document):
        root, title = found
        text = _flow(root, page_url, downloads)
        if title and not re.search(rf"^#+ {re.escape(title)}\s*$", text, re.M):
            text = f"# {title}\n\n{text}" if text else f"# {title}"
        return text, downloads
    text = _flow(article_root(document), page_url, downloads)
    title_node = document.find(".//h1")
    if title_node is not None:
        title = " ".join(_inline(title_node, page_url, downloads).split())
        heading = f"# {title}"
        if title and heading not in text:
            text = f"{heading}\n\n{text}" if text else heading
    return text, downloads


def _render(node, page_url: str, downloads: dict[str, str]) -> str:
    if not isinstance(node.tag, str):
        return ""
    math = math_source(node)
    if math is not None:
        source, display = math
        return f"$$\n{source}\n$$" if display else f"${source}$"
    if node.tag == "style" or node.get("type") == "text/front-matter":
        return ""
    if node.tag in {"script", "template", "nav"}:
        return ""
    if holds_templates(node):
        return _crop(page_url, selector(node))
    if node.tag == "iframe":
        address = _absolute(page_url, node.get("src") or "")
        return _crop(address, None) if address else ""
    if live_figure(node):
        return _crop(page_url, selector(node))
    if widget(node) and not contains_prose(node):
        # A script's mount named for comments, a menu or a banner is the site's, not the article's.
        if NEGATIVE.search(f"{node.get('id') or ''} {node.get('class') or ''}"):
            return ""
        return _crop(page_url, selector(node))
    if widget(node):
        return "\n\n".join(_render(child, page_url, downloads) for child in node)
    tag = node.tag.lower()
    if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        title = _inline(node, page_url, downloads)
        return f"{'#' * int(tag[1])} {title}" if title else ""
    if tag in {"ul", "ol"}:
        return _list(node, ordered=tag == "ol", page_url=page_url, downloads=downloads)
    if tag == "blockquote":
        # Its paragraphs and lists stay apart, under one mark that keeps the quote one block.
        return "\n".join(f"> {line}".rstrip() for line in _flow(node, page_url, downloads).splitlines())
    if tag == "pre":
        code = node.find("code")
        body = code.text_content() if code is not None else node.text_content()
        return f"```\n{body.rstrip()}\n```"
    if tag == "table":
        return _table(node, page_url, downloads)
    if tag == "img":
        return _image(node, page_url, downloads)
    if tag == "video":
        return _video(node, page_url, downloads)
    return _flow(node, page_url, downloads)


def _flow(node, page_url: str, downloads: dict[str, str]) -> str:
    """A container's content in document order. Its own text and inline children gather into paragraphs and
    block children stand between them, so text a site puts straight into a div reads like any <p>."""
    blocks: list[str] = []
    run: list[str | _Emphasis] = [node.text or ""]

    def close_paragraph():
        paragraph = _joined(run).strip()
        if paragraph:
            blocks.append(paragraph)
        run.clear()

    for child in node:
        if block(child):
            close_paragraph()
            blocks.append(_render(child, page_url, downloads))
        else:
            run.append(_piece(child, page_url, downloads))
        run.append(child.tail or "")
    close_paragraph()
    return "\n\n".join(written for written in blocks if written.strip())


def _crop(page_url: str, css: str | None) -> str:
    lines = page_url if css is None else f"{page_url}\n{css}"
    return f"```fnmn-interactive\n{lines}\n```"


def _list(node, ordered: bool, page_url: str, downloads: dict[str, str]) -> str:
    """An item's paragraphs and inner lists go on lines of their own, set in under its marker, so they stay apart
    and in the item. A blank line between them would end the list."""
    items = [_flow(child, page_url, downloads) for child in node if child.tag == "li"]
    lines = []
    for index, item in enumerate(filter(None, items), 1):
        marker = f"{index}. " if ordered else "- "
        lines.append(marker + ("\n" + " " * len(marker)).join(line for line in item.splitlines() if line.strip()))
    return "\n".join(lines)


def _table(node, page_url: str, downloads: dict[str, str]) -> str:
    rows = [child for child in node.iter("tr")]
    if not rows:
        return ""
    rendered = ["| " + " | ".join(_cells(row, page_url, downloads)) + " |" for row in rows]
    width = rendered[0].count("|") - 1
    rendered.insert(1, "| " + " | ".join("---" for _ in range(width)) + " |")
    return "\n".join(rendered)


def _cells(row, page_url: str, downloads: dict[str, str]) -> list[str]:
    return [_inline(cell, page_url, downloads).replace("|", "\\|") for cell in row if cell.tag in {"td", "th"}]


def _image(node, page_url: str, downloads: dict[str, str]) -> str:
    """A picture of the text. One the page draws at icon size is an avatar or a logo, not part of the article, and
    one already shown is a copy a lazy-loading page keeps beside it."""
    if any(int(size) <= 64 for size in (node.get("width"), node.get("height")) if size and size.isdigit()):
        return ""
    source = node.get("src") or ""
    if source and not source.startswith("data:") and _absolute(page_url, source) in downloads.values():
        return ""
    alt = node.get("alt") or ""
    src = _stored(page_url, source, downloads)
    return f"![{alt}]({src})"


def _video(node, page_url: str, downloads: dict[str, str]) -> str:
    source = node.get("src") or ""
    nested = node.find("source")
    if not source and nested is not None:
        source = nested.get("src") or ""
    return f"```fnmn-video\n{_stored(page_url, source, downloads)}\n```"


def _stored(page_url: str, src: str, downloads: dict[str, str]) -> str:
    if not src or src.startswith("data:"):
        return src
    absolute = _absolute(page_url, src)
    for path, existing in downloads.items():
        if existing == absolute:
            return path
    suffix = Path(urlparse(absolute).path).suffix.lower()
    if suffix not in _ASSET_EXTENSIONS:
        suffix = ""
    path = asset_path(absolute, suffix)
    downloads[path] = absolute
    return path


def _absolute(page_url: str, src: str) -> str:
    return urljoin(page_url, src)


def _inline(node, page_url: str, downloads: dict[str, str]) -> str:
    return _inline_spaced(node, page_url, downloads).strip()


def _inline_spaced(node, page_url: str, downloads: dict[str, str]) -> str:
    parts = [node.text or ""]
    for child in node:
        parts.append(_piece(child, page_url, downloads))
        parts.append(child.tail or "")
    return _joined(parts)


_BOLD_TAGS = {"strong", "b"}
_ITALIC_TAGS = {"em", "i"}


@dataclass(frozen=True)
class _Emphasis:
    """Bold or italic text, with the spaces at its edges, whose marks are written once the characters on both
    sides of it are known."""

    text: str
    mark: str


def _emphasis(node, mark: str, page_url: str, downloads: dict[str, str]) -> str | _Emphasis:
    """Bold inside bold, as `<b><strong>`, adds no marks of its own."""
    family = _BOLD_TAGS if node.tag in _BOLD_TAGS else _ITALIC_TAGS
    text = _inline_spaced(node, page_url, downloads)
    if any(outer.tag in family for outer in node.iterancestors()):
        return text
    return _Emphasis(text, mark)


def _joined(parts: list[str | _Emphasis]) -> str:
    """Inline pieces as one run of Markdown. Two runs of one emphasis side by side, as `<b>a</b><b>b</b>`, are one
    run: `**a****b**` pairs its marks wrongly. A mark goes where CommonMark reads it: a run that starts with
    punctuation opens only after a space or punctuation, and one that ends with it closes only before them, so
    `<b>Eyes:</b>green` gets a space after its marks instead of reading as `**Eyes:**green` with the stars in it."""
    merged: list[str | _Emphasis] = []
    for part in parts:
        if not part:
            continue
        previous = merged[-1] if merged else None
        if isinstance(part, _Emphasis) and isinstance(previous, _Emphasis) and previous.mark == part.mark:
            merged[-1] = _Emphasis(previous.text + part.text, part.mark)
        else:
            merged.append(part)
    written = ""
    for index, part in enumerate(merged):
        if isinstance(part, str):
            written += part
            continue
        inner = part.text.strip()
        if not inner:
            written += part.text
            continue
        lead = part.text[: len(part.text) - len(part.text.lstrip())]
        trail = part.text[len(part.text.rstrip()) :]
        before = lead[-1:] or written[-1:] or " "
        after = trail[:1] or _first_character(merged[index + 1 :])
        # A mark next to another emphasis's marks is one run of stars with them, so it is the text inside that counts.
        first, last = inner.lstrip("*")[:1] or "*", inner.rstrip("*")[-1:] or "*"
        written += lead
        if before.isalnum() and punctuation(first) and first not in CLOSING_PUNCTUATION:
            written += " "
        written += part.mark + inner + part.mark
        if after.isalnum() and punctuation(last) and last not in OPENING_PUNCTUATION:
            written += " "
        written += trail
    return written


def _first_character(parts: list[str | _Emphasis]) -> str:
    """The first character the pieces will write: an emphasis that opens without a space opens with its mark."""
    for part in parts:
        if isinstance(part, str):
            return part[0]
        return part.text[0] if part.text[0].isspace() else part.mark[0]
    return " "


def _wrapped(text: str, opening: str, closing: str) -> str:
    """Spaces at the edges of `<b>word </b>` or `<a>word </a>` stay outside the marks: Markdown takes `**word **`
    for plain text, and a dropped space glues the word to the next one."""
    inner = text.strip()
    if not inner:
        return text
    return text[: len(text) - len(text.lstrip())] + opening + inner + closing + text[len(text.rstrip()) :]


def _code(text: str) -> str:
    """Code shows its text as it is, so a link or bold inside it gets no marks. Its fence is longer than any run of
    backticks in it, with a space inside when the code starts or ends with one, and the spaces at the edges of
    `<code>word </code>` stay outside it, between the code and the next word."""
    inner = text.strip()
    if not inner:
        return text
    fence = "`" * (max((len(run) for run in re.findall(r"`+", inner)), default=0) + 1)
    pad = " " if inner.startswith("`") or inner.endswith("`") else ""
    return _wrapped(text, fence + pad, pad + fence)


def _piece(node, page_url: str, downloads: dict[str, str]) -> str | _Emphasis:
    """One inline element as Markdown, without the text that follows it."""
    if not isinstance(node.tag, str):
        return ""
    math = math_source(node)
    if math is not None:
        source, display = math
        return f"$$\n{source}\n$$" if display else f"${source}$"
    if node.tag in {"style", "script", "button", "select", "textarea"}:
        return ""
    if node.tag in _ITALIC_TAGS:
        return _emphasis(node, "*", page_url, downloads)
    if node.tag in _BOLD_TAGS:
        return _emphasis(node, "**", page_url, downloads)
    if node.tag == "code":
        return _code(node.text_content())
    if node.tag == "a":
        label = _inline_spaced(node, page_url, downloads)
        return _wrapped(label, "[", f"]({_absolute(page_url, node.get('href') or '')})") if label.strip() else label
    if node.tag == "img":
        return _image(node, page_url, downloads)
    if node.tag == "br":
        return "\n"
    # A span keeps the spaces at its edges: sites put the space between two words inside one of them.
    return _inline_spaced(node, page_url, downloads)

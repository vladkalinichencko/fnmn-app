from __future__ import annotations

import hashlib
import re
from pathlib import Path
from urllib.parse import urljoin, urlparse

from lxml import html

_PROSE = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote", "table", "pre"}
_BLOCKS = _PROSE | {"figure", "div", "section", "img", "video", "iframe"}
_SCORE_TAGS = {"section", "h2", "h3", "h4", "h5", "h6", "p", "td", "pre"}
_POSITIVE = re.compile(r"article|body|content|entry|main|page|post|text|blog|story", re.I)
_NEGATIVE = re.compile(r"banner|comment|footer|header|menu|nav|related|sidebar|sponsor", re.I)
_ASSET_EXTENSIONS = {".gif", ".png", ".jpg", ".jpeg", ".webp", ".svg", ".mp4", ".webm", ".mov"}
_TEX = './/*[local-name()="annotation"][@encoding="application/x-tex"]'


def article_markdown(source: str, page_url: str) -> tuple[str, dict[str, str]]:
    document = html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))
    root = _article_root(document)
    downloads: dict[str, str] = {}
    blocks = [_render(child, page_url, downloads) for child in root]
    text = "\n\n".join(block for block in blocks if block.strip())
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
    math = _math_source(node)
    if math is not None:
        source, display = math
        return f"$$\n{source}\n$$" if display else f"${source}$"
    if node.tag == "style" or node.get("type") == "text/front-matter":
        return ""
    if node.tag == "script":
        return ""
    if node.tag == "iframe":
        address = _absolute(page_url, node.get("src") or "")
        return _crop(address, None) if address else ""
    if node.tag == "figure" and not _picture(node):
        return _crop(page_url, _selector(node))
    if _widget(node) and not _contains_prose(node):
        return _crop(page_url, _selector(node))
    if _widget(node):
        return "\n\n".join(_render(child, page_url, downloads) for child in node)
    tag = node.tag.lower()
    if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        return f"{'#' * int(tag[1])} {_inline(node, page_url, downloads)}"
    if tag in {"ul", "ol"}:
        return _list(node, ordered=tag == "ol", page_url=page_url, downloads=downloads)
    if tag == "blockquote":
        return "\n".join(f"> {line}" for line in _inline(node, page_url, downloads).splitlines())
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
    if any(isinstance(child.tag, str) and child.tag in _BLOCKS for child in node):
        return "\n\n".join(block for block in (_render(child, page_url, downloads) for child in node) if block.strip())
    return _inline(node, page_url, downloads)


def _article_root(document):
    scores: dict = {}
    for node in document.iter():
        if not isinstance(node.tag, str) or node.tag not in _SCORE_TAGS:
            continue
        if node.xpath("ancestor::script or ancestor::style"):
            continue
        text = " ".join(node.text_content().split())
        if len(text) < 25:
            continue
        score = 1 + text.count(",") + min(len(text) // 100, 3)
        parent = node.getparent()
        level = 0
        while parent is not None and isinstance(parent.tag, str) and parent.tag != "html" and level < 4:
            divider = 1 if level == 0 else 2 if level == 1 else level * 3
            scores[parent] = scores.get(parent, 0) + score / divider
            parent = parent.getparent()
            level += 1
    if not scores:
        body = document.find(".//body")
        return body if body is not None else document

    def weighed(node):
        score = scores[node]
        name = f"{node.get('id') or ''} {node.get('class') or ''}"
        if _NEGATIVE.search(name):
            score -= 25
        if _POSITIVE.search(name):
            score += 25
        total = len(" ".join(node.text_content().split())) or 1
        linked = sum(len(" ".join(link.text_content().split())) for link in node.xpath(".//a"))
        return score * (1 - min(linked / total, 1))

    winner = max(scores, key=weighed)
    if winner.tag == "body":
        inner = [
            node for node in scores
            if node is not winner and node.tag != "body" and weighed(node) > weighed(winner) * 0.3
        ]
        if inner:
            winner = max(inner, key=weighed)
    parent = winner.getparent()
    if parent is not None and isinstance(parent.tag, str) and parent.tag not in {"html", "body"}:
        others = sum(scores.get(child, 0) for child in parent if child is not winner)
        if others > scores[winner] * 0.5:
            return parent
    return winner


def _picture(node) -> bool:
    return bool(node.xpath(".//img")) and not _widget(node)


def _widget(node) -> bool:
    for candidate in node.iter():
        if not isinstance(candidate.tag, str) or _math_source(candidate) is not None:
            continue
        if candidate.tag in {"canvas", "iframe"}:
            return True
        if candidate.tag == "script":
            return True
        if candidate.tag in {"div", "svg"} and candidate.get("id") and not " ".join(candidate.text_content().split()):
            return True
    return False


def _contains_prose(node) -> bool:
    return any(isinstance(child.tag, str) and child.tag in _PROSE for child in node.iter() if child is not node)


def _crop(page_url: str, selector: str | None) -> str:
    lines = page_url if selector is None else f"{page_url}\n{selector}"
    return f"```fnmn-interactive\n{lines}\n```"


def _selector(node) -> str:
    identifier = node.get("id") or ""
    if re.fullmatch(r"[A-Za-z_][\w-]*", identifier):
        return f"#{identifier}"
    parts: list[str] = []
    current = node
    while isinstance(getattr(current, "tag", None), str) and current.tag != "html":
        parent = current.getparent()
        if parent is None:
            parts.append(current.tag)
            break
        index = 1
        for sibling in parent:
            if not isinstance(sibling.tag, str) or sibling.tag != current.tag:
                continue
            if sibling is current:
                break
            index += 1
        parts.append(f"{current.tag}:nth-of-type({index})")
        if current.tag == "body":
            break
        current = parent
    return " > ".join(reversed(parts))


def _list(node, ordered: bool, page_url: str, downloads: dict[str, str]) -> str:
    lines = []
    for index, item in enumerate((child for child in node if child.tag == "li"), 1):
        marker = f"{index}." if ordered else "-"
        lines.append(f"{marker} {_inline(item, page_url, downloads)}")
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
    alt = node.get("alt") or ""
    src = _stored(page_url, node.get("src") or "", downloads)
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
    name = hashlib.sha256(absolute.encode()).hexdigest()[:16]
    path = f"assets/{name}{suffix}"
    downloads[path] = absolute
    return path


def _absolute(page_url: str, src: str) -> str:
    return urljoin(page_url, src)


def _inline(node, page_url: str, downloads: dict[str, str]) -> str:
    parts: list[str] = []
    if node.text:
        parts.append(node.text)
    for child in node:
        if not isinstance(child.tag, str):
            if child.tail:
                parts.append(child.tail)
            continue
        if child.tag in {"style", "script"} and _math_source(child) is None:
            if child.tail:
                parts.append(child.tail)
            continue
        if child.tag in {"em", "i"}:
            parts.append(f"*{_inline(child, page_url, downloads)}*")
        elif child.tag in {"strong", "b"}:
            parts.append(f"**{_inline(child, page_url, downloads)}**")
        elif child.tag == "code":
            parts.append(f"`{_inline(child, page_url, downloads)}`")
        elif child.tag == "a":
            href = _absolute(page_url, child.get("href") or "")
            parts.append(f"[{_inline(child, page_url, downloads)}]({href})")
        elif child.tag == "img":
            parts.append(_image(child, page_url, downloads))
        elif child.tag == "br":
            parts.append("\n")
        elif _math_source(child) is not None:
            source, display = _math_source(child)
            parts.append(f"$$\n{source}\n$$" if display else f"${source}$")
        else:
            parts.append(_inline(child, page_url, downloads))
        if child.tail:
            parts.append(child.tail)
    return "".join(parts).strip()


def _math_source(node) -> tuple[str, bool] | None:
    kind = node.get("type") or ""
    if node.tag == "script" and "math/tex" in kind:
        return (node.text or "").strip(), "display" in kind
    if node.tag == "math":
        tex = _tex(node) or (node.get("alttext") or "").strip()
        if tex:
            return tex, _displayed(node)
    annotations = _annotations(node)
    if len(annotations) != 1 or not _formula_box(node):
        return None
    parent = node.getparent()
    if parent is not None and len(_annotations(parent)) == 1 and _formula_box(parent):
        return None
    return _tex(node), _displayed(node)


def _annotations(node):
    return [item for item in node.xpath(_TEX) if item.text and item.text.strip()]


def _formula_box(node) -> bool:
    if node.tag == "math":
        return True
    tokens = set((node.get("class") or "").split())
    if "katex" in tokens or "katex-display" in tokens:
        return True
    return any("katex-html" in set((child.get("class") or "").split()) for child in node if isinstance(child.tag, str))


def _displayed(node) -> bool:
    if node.xpath('.//*[local-name()="math"][@display="block"]') or (
        node.tag == "math" and node.get("display") == "block"
    ):
        return True
    return bool(
        node.xpath(
            'ancestor-or-self::*[contains(concat(" ", normalize-space(@class), " "), " katex-display ")]'
            '|.//*[contains(concat(" ", normalize-space(@class), " "), " katex-display ")]'
        )
    )


def _tex(node) -> str:
    found = _annotations(node)
    return found[0].text.strip() if found else ""

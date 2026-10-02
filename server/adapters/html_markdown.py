from __future__ import annotations

import copy
import hashlib
import re
from pathlib import Path
from urllib.parse import urljoin, urlparse

import trafilatura
from lxml import etree, html

_PROSE = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote", "table", "pre"}
_BLOCKS = _PROSE | {"figure", "div", "section", "img", "video", "iframe"}
_SECTIONS = {"article", "main", "header", "footer", "aside", "nav"}
_SCORE_TAGS = {"section", "h2", "h3", "h4", "h5", "h6", "p", "td", "pre"}
_POSITIVE = re.compile(r"article|body|content|entry|main|page|post|text|blog|story", re.I)
_NEGATIVE = re.compile(r"banner|comment|consent|cookie|disqus|footer|header|menu|nav|onetrust|related|sidebar|sponsor", re.I)
_ASSET_EXTENSIONS = {".gif", ".png", ".jpg", ".jpeg", ".webp", ".svg", ".mp4", ".webm", ".mov"}
_TEX = './/*[local-name()="annotation"][@encoding="application/x-tex"]'


def article_markdown(source: str, page_url: str) -> tuple[str, dict[str, str]]:
    document = html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))
    document.make_links_absolute(page_url, resolve_base_href=True, handle_failures="ignore")
    downloads: dict[str, str] = {}
    if found := _main_content(document):
        root, title = found
        text = _flow(root, page_url, downloads)
        if title and not re.search(rf"^#+ {re.escape(title)}\s*$", text, re.M):
            text = f"# {title}\n\n{text}" if text else f"# {title}"
        return text, downloads
    text = _flow(_article_root(document), page_url, downloads)
    title_node = document.find(".//h1")
    if title_node is not None:
        title = " ".join(_inline(title_node, page_url, downloads).split())
        heading = f"# {title}"
        if title and heading not in text:
            text = f"{heading}\n\n{text}" if text else heading
    return text, downloads


def _main_content(document):
    """The article as Trafilatura finds it, and its title, kept in the page's own markup so formulas, videos and
    live figures still reach the renderer. Every element that owns text gets a marker word in a copy of the page;
    Trafilatura reads the copy, and an owner whose marker it dropped is dropped from the page: bylines, buttons,
    comments, related stories. Pictures it dropped go too, and so does a container left with nothing in it. The
    article is the smallest element holding everything kept, together with the figures, pictures and formulas
    beside it; what lies before or after them is page furniture. A page Trafilatura cannot read returns None."""
    _drop_sign_ups(document)
    formulas = _formula_parts(document)
    drawn = {node for figure in document.iter("figure") if _live_figure(figure) for node in figure.iter()}
    owners: dict = {}
    for node in document.iter():
        if not isinstance(node.tag, str) or node in formulas or node in drawn or node.tag in _SILENT:
            continue
        if not (node.text or "").strip() and not any((child.tail or "").strip() for child in node):
            continue
        owner = _owner(node)
        if owner is not None:
            owners.setdefault(owner, len(owners))
    if not owners:
        return None
    marked = copy.deepcopy(document)
    copies = dict(zip(document.iter(), marked.iter()))
    for owner, number in owners.items():
        # The marker goes before the owner's first words, which may follow a child: an old wiki writes its
        # article after the heading's <div>, straight into the cell.
        twin = copies[owner]
        holder = next((child for child in twin if (child.tail or "").strip()), None)
        if (twin.text or "").strip() or holder is None:
            twin.text = f"{_MARK}{number}x {twin.text or ''}"
        else:
            holder.tail = f"{_MARK}{number}x {holder.tail}"
    found = trafilatura.extract(html.tostring(marked, encoding="unicode"), output_format="xml",
                                include_images=True, include_tables=True, include_comments=False)
    if not found:
        return None
    extracted = etree.fromstring(found.encode())
    kept_numbers = {int(number) for number in re.findall(rf"{_MARK}(\d+)x", found)}
    kept = [owner for owner, number in owners.items() if number in kept_numbers]
    if not kept:
        return None
    heading = _title(document, set(kept))
    pictures = {graphic.get("src") for graphic in extracted.iter("graphic")}
    if pictures:
        for image in list(document.iter("img")):
            if pictures & set(image.attrib.values()):
                kept.append(image)
            else:
                _drop_emptied(image)
    for owner, number in owners.items():
        if number not in kept_numbers and owner.getparent() is not None and _furniture(owner):
            _drop_own_text(owner)
            _drop_emptied(owner)
    page = document.getroottree().getroot()
    kept = [node for node in kept if node is page or page in node.iterancestors()]
    if not kept:
        return None
    root = _common_ancestor(kept)
    while root.getparent() is not None and root.getparent().tag not in {"body", "html"} and any(
        sibling is not root and (sibling in formulas or _closes_article(sibling)) for sibling in root.getparent()
    ):
        root = root.getparent()
    # Long text Trafilatura left out beside the article is the article's too, an FAQ or a list of chapters,
    # unless it sits in comments, a sidebar or a footer.
    told = [owner for owner in owners if not _furniture(owner) and not _aside(owner, root)]
    _trim_edges(root, kept + told, formulas)
    # The article opens at its own title: what stands above it is the site's header. The title is not repeated.
    if heading is not None and (heading is root or root in heading.iterancestors()):
        _open_at(root, heading)
        return root, None
    return root, _heading_text(heading) if heading is not None else None


def _drop_sign_ups(document) -> None:
    """A box that asks for an email or a search word sits inside the article on many sites. It is the largest
    element around the field whose text stays a few lines long; the article around it is far longer."""
    for field in document.xpath('//input[not(@type) or @type="text" or @type="email" or @type="search"]'):
        box = field
        for parent in field.iterancestors():
            if parent.tag in {"body", "html"} or len(" ".join(parent.text_content().split())) > 300:
                break
            box = parent
        if box.getparent() is not None:
            box.drop_tree()


def _title(document, kept: set):
    """The article's own heading. The page names it for sharing in og:title, and a heading with that text is
    it, even an <h3> under a blog's <h1>. Otherwise it is the longest heading found in the page's <title>, which
    holds the site's name as well. A page whose <title> names neither, such as "Article", has its title in the
    first <h1> Trafilatura kept, or else in the first <h1>."""
    shared = " ".join((document.xpath('string(//meta[@property="og:title"]/@content)') or "").split()).casefold()
    headings = [heading for heading in document.xpath("//h1 | //h2 | //h3") if _heading_text(heading)]
    if shared:
        for heading in headings:
            if _heading_text(heading).casefold() == shared:
                return heading
    page = " ".join((document.findtext(".//title") or "").split()).casefold()
    named = [heading for heading in headings if _heading_text(heading).casefold() in page]
    if named:
        return max(named, key=lambda heading: len(_heading_text(heading)))
    first = [heading for heading in headings if heading.tag == "h1"]
    return next((heading for heading in first if heading in kept), first[0] if first else None)


def _open_at(root, heading) -> None:
    """Drops what comes before the article's title inside it, and a later heading that repeats the title. A
    header is a few lines; with more text above it, the heading is not where the article starts."""
    above = set(heading.iterancestors())
    text = _heading_text(heading).casefold()
    order = list(root.iter())
    words = 0
    for node in order[:order.index(heading)]:
        if isinstance(node.tag, str) and node not in above:
            words += len((node.text or "").split())
        words += len((node.tail or "").split()) if node not in above else 0
    header = words < 80
    passed = False
    for node in list(root.iter()):
        if node is heading:
            passed = True
        elif not passed and header and node not in above and node.getparent() is not None:
            node.drop_tree()
        elif passed and node.tag in {"h1", "h2", "h3"} and _heading_text(node).casefold() == text:
            node.drop_tree()


def _heading_text(node) -> str:
    """A heading's words, with a line break inside it read as a space."""
    return " ".join(" ".join(node.itertext()).split())


_MARK = "fnmnblock"
_MEDIA = {"img", "picture", "video", "audio", "iframe", "canvas", "math", "object", "embed"}
_SILENT = {"script", "style", "template", "noscript", "head", "title", "meta", "link", "button"}
_INLINE = {"a", "abbr", "b", "bdi", "bdo", "br", "cite", "code", "data", "del", "dfn", "em", "font", "i", "ins", "kbd",
           "label", "mark", "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var", "wbr"}


def _formula_parts(document) -> set:
    """Everything inside a formula: its glyphs are not text of their own, the paragraph around them is."""
    parts = set()
    if not document.xpath(f'boolean({_TEX[1:]} | //*[local-name()="math"] | //script[contains(@type, "math/tex")])'):
        return parts
    for node in document.iter():
        if isinstance(node.tag, str) and node not in parts and _math_source(node) is not None:
            parts.update(node.iter())
    return parts


def _owner(node):
    """The element a piece of text belongs to: the nearest one around it that is not inline."""
    for candidate in (node, *node.iterancestors()):
        if not isinstance(candidate.tag, str) or candidate.tag in _SILENT:
            return None
        if not _inline_element(candidate):
            return candidate
    return None


def _inline_element(node) -> bool:
    """A link wrapped around a whole card is a block, not a word in a sentence."""
    return node.tag in _INLINE and not _block(node)


def _furniture(owner) -> bool:
    """Trafilatura leaves out headings and long paragraphs of real articles too, so inside the article only a
    short line it dropped goes: a byline, a date, Follow, Share, a reading time. Long text it dropped before or
    after the article goes with the edges."""
    if owner.tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        return False
    own = [owner.text or ""]
    for child in owner:
        if isinstance(child.tag, str) and _inline_element(child):
            own.append(child.text_content())
        own.append(child.tail or "")
    return len("".join(own).split()) <= 12


def _drop_own_text(owner) -> None:
    """Takes away an owner's text and inline elements; the blocks inside it stand on their own."""
    owner.text = None
    for child in list(owner):
        if isinstance(child.tag, str) and not _inline_element(child):
            child.tail = None
        elif isinstance(child.tag, str) and any(not _inline_element(inner) for inner in child.iterdescendants() if isinstance(inner.tag, str)):
            # An inline element wrapped around blocks, a <span> holding paragraphs, keeps them.
            child.text = child.tail = None
        else:
            owner.remove(child)


def _drop_emptied(node) -> None:
    """Removes an element that lost its content, and each container around it left empty by that. They all had
    something before, so an empty mount a script fills later is never taken for one of them."""
    while node.getparent() is not None and not "".join(node.itertext()).strip() and not _holds_media(node):
        parent = node.getparent()
        node.drop_tree()
        node = parent


def _holds_media(node) -> bool:
    return any(isinstance(inner.tag, str) and inner.tag in _MEDIA for inner in node.iter())


def _common_ancestor(nodes):
    paths = [[node, *node.iterancestors()][::-1] for node in nodes]
    common = paths[0]
    for path in paths[1:]:
        length = 0
        while length < min(len(common), len(path)) and common[length] is path[length]:
            length += 1
        common = common[:length]
    return common[-1]


def _aside(node, root) -> bool:
    """Whether an element sits in a part of the article named for comments, a menu, a footer and the like."""
    for ancestor in (node, *node.iterancestors()):
        if ancestor is root:
            return False
        if _NEGATIVE.search(f"{ancestor.get('id') or ''} {ancestor.get('class') or ''}"):
            return True
    return False


def _trim_edges(root, kept, formulas) -> None:
    """Drops what lies before the first kept element and after the last. A formula, a picture, a video or a live
    figure owns no text for Trafilatura to keep, so one of them inside the article can open or end it as well."""
    order = {node: index for index, node in enumerate(root.iter())}
    closing = [node for node in kept if node in order]
    closing += [node for node in order if node in formulas or _closes_article(node)]
    first = min(order[node] for node in closing)
    end = max(order[inner] for node in closing for inner in node.iter())
    holders = {root} | {ancestor for node in closing for ancestor in node.iterancestors()}
    for node in list(root.iter()):
        if node in holders or node.getparent() is None:
            continue
        # A link in the text of an element that stays is part of that text, wherever it sits.
        if isinstance(node.tag, str) and _inline_element(node) and _owner(node) in holders:
            continue
        index = order[node]
        if index < first or index > end:
            node.drop_tree()


def _closes_article(node) -> bool:
    """Content without text: media, a figure, or a mount a script draws into."""
    if not isinstance(node.tag, str):
        return False
    if node.tag in _MEDIA or node.tag == "figure":
        return True
    mount = bool(node.get("id")) and node.tag in {"div", "svg"} and not "".join(node.itertext()).strip()
    return mount and not _NEGATIVE.search(f"{node.get('id')} {node.get('class') or ''}")


def _render(node, page_url: str, downloads: dict[str, str]) -> str:
    if not isinstance(node.tag, str):
        return ""
    math = _math_source(node)
    if math is not None:
        source, display = math
        return f"$$\n{source}\n$$" if display else f"${source}$"
    if node.tag == "style" or node.get("type") == "text/front-matter":
        return ""
    if node.tag in {"script", "template", "nav"}:
        return ""
    if _holds_templates(node):
        return _crop(page_url, _selector(node))
    if node.tag == "iframe":
        address = _absolute(page_url, node.get("src") or "")
        return _crop(address, None) if address else ""
    if _live_figure(node):
        return _crop(page_url, _selector(node))
    if _widget(node) and not _contains_prose(node):
        # A script's mount named for comments, a menu or a banner is the site's, not the article's.
        if _NEGATIVE.search(f"{node.get('id') or ''} {node.get('class') or ''}"):
            return ""
        return _crop(page_url, _selector(node))
    if _widget(node):
        return "\n\n".join(_render(child, page_url, downloads) for child in node)
    tag = node.tag.lower()
    if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        title = _inline(node, page_url, downloads)
        return f"{'#' * int(tag[1])} {title}" if title else ""
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
    return _flow(node, page_url, downloads)


def _flow(node, page_url: str, downloads: dict[str, str]) -> str:
    """A container's content in document order. Its own text and inline children gather into paragraphs and
    block children stand between them, so text a site puts straight into a div reads like any <p>."""
    blocks: list[str] = []
    run: list[str] = [node.text or ""]

    def close_paragraph():
        paragraph = "".join(run).strip()
        if paragraph:
            blocks.append(paragraph)
        run.clear()

    for child in node:
        if _block(child):
            close_paragraph()
            blocks.append(_render(child, page_url, downloads))
        else:
            run.append(_piece(child, page_url, downloads))
        run.append(child.tail or "")
    close_paragraph()
    return "\n\n".join(block for block in blocks if block.strip())


def _block(node) -> bool:
    """An element that stands on its own line, or any wrapper around one. A picture inside a span stays in its sentence."""
    if not isinstance(node.tag, str):
        return False
    if node.tag in _BLOCKS or node.tag in _SECTIONS:
        return True
    return any(isinstance(inner.tag, str) and inner.tag in _BLOCKS - {"img"} for inner in node.iterdescendants())


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


def _holds_templates(node) -> bool:
    """A widget whose states wait in <template> elements next to its controls: the page shows one at a time,
    so it is read in the page and not as all of them at once."""
    children = [child for child in node if isinstance(child.tag, str)]
    return any(map(_inert, children)) and not all(map(_inert, children))


def _inert(node) -> bool:
    return node.tag == "template" or (len(node) > 0 and all(child.tag == "template" for child in node))


def _live_figure(node) -> bool:
    """A figure the page draws itself, read as a crop of the live page with its caption. A figure of a picture,
    of an embedded video or of a pull quote reads as what it holds."""
    return node.tag == "figure" and not _picture(node) and not node.xpath(".//iframe | ./blockquote")


def _picture(node) -> bool:
    return bool(node.xpath(".//img")) and not _widget(node)


def _widget(node) -> bool:
    for candidate in node.iter():
        if not isinstance(candidate.tag, str) or _math_source(candidate) is not None:
            continue
        if candidate.tag == "canvas":
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
    items = [_inline(child, page_url, downloads) for child in node if child.tag == "li"]
    lines = [f"{index}. {item}" if ordered else f"- {item}" for index, item in enumerate(filter(None, items), 1)]
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
    name = hashlib.sha256(absolute.encode()).hexdigest()[:16]
    path = f"assets/{name}{suffix}"
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
    return "".join(parts)


def _emphasis(node, mark: str, page_url: str, downloads: dict[str, str]) -> str:
    """Spaces at the edges of `<b>word </b>` stay outside the marks: Markdown takes `**word **` for plain text,
    and a stripped space glues the word to the next one. Bold inside bold adds no marks of its own."""
    text = _inline_spaced(node, page_url, downloads)
    inner = text.strip()
    if not inner or any(outer.tag == node.tag for outer in node.iterancestors()):
        return text
    return text[: len(text) - len(text.lstrip())] + mark + inner + mark + text[len(text.rstrip()) :]


def _piece(node, page_url: str, downloads: dict[str, str]) -> str:
    """One inline element as Markdown, without the text that follows it."""
    if not isinstance(node.tag, str):
        return ""
    math = _math_source(node)
    if math is not None:
        source, display = math
        return f"$$\n{source}\n$$" if display else f"${source}$"
    if node.tag in {"style", "script", "button", "select", "textarea"}:
        return ""
    if node.tag in {"em", "i"}:
        return _emphasis(node, "*", page_url, downloads)
    if node.tag in {"strong", "b"}:
        return _emphasis(node, "**", page_url, downloads)
    if node.tag == "code":
        return f"`{_inline(node, page_url, downloads)}`"
    if node.tag == "a":
        label = _inline(node, page_url, downloads)
        return f"[{label}]({_absolute(page_url, node.get('href') or '')})" if label else ""
    if node.tag == "img":
        return _image(node, page_url, downloads)
    if node.tag == "br":
        return "\n"
    return _inline(node, page_url, downloads)


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

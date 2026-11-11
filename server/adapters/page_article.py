"""Where the article stands on a web page, and what each of its elements is: prose, a block, a formula, a picture,
a figure the page draws itself. The page's own tree is cut down to the article here; `html_markdown` writes it."""

from __future__ import annotations

import copy
import re

import trafilatura
from lxml import etree, html

PROSE = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote", "table", "pre"}
_BLOCKS = PROSE | {"figure", "div", "section", "img", "video", "iframe"}
_SECTIONS = {"article", "main", "header", "footer", "aside", "nav"}
_SCORE_TAGS = {"section", "h2", "h3", "h4", "h5", "h6", "p", "td", "pre"}
_POSITIVE = re.compile(r"article|body|content|entry|main|page|post|text|blog|story", re.I)
NEGATIVE = re.compile(r"banner|comment|consent|cookie|disqus|footer|header|menu|nav|onetrust|related|sidebar|sponsor", re.I)
_TEX = './/*[local-name()="annotation"][@encoding="application/x-tex"]'
_MARK = "fnmnblock"
_MEDIA = {"img", "picture", "video", "audio", "iframe", "canvas", "math", "object", "embed"}
_SILENT = {"script", "style", "template", "noscript", "head", "title", "meta", "link", "button"}
_INLINE = {"a", "abbr", "b", "bdi", "bdo", "br", "cite", "code", "data", "del", "dfn", "em", "font", "i", "ins", "kbd",
           "label", "mark", "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var", "wbr"}


def main_content(document):
    """The article as Trafilatura finds it, and its title, kept in the page's own markup so formulas, videos and
    live figures still reach the renderer. Every element that owns text gets a marker word in a copy of the page;
    Trafilatura reads the copy, and an owner whose marker it dropped is dropped from the page: bylines, buttons,
    comments, related stories. Pictures it dropped go too, and so does a container left with nothing in it. The
    article is the smallest element holding everything kept, together with the figures, pictures and formulas
    beside it; what lies before or after them is page furniture. A page Trafilatura cannot read returns None."""
    _drop_sign_ups(document)
    formulas = _formula_parts(document)
    drawn = {node for figure in document.iter("figure") if live_figure(figure) for node in figure.iter()}
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
    told = [owner for owner in owners if not _furniture(owner) and not _aside(owner, root)]
    _trim_edges(root, kept + told, formulas)
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
    if header:
        for figure in [node for node in above if node.tag == "figure" and root in node.iterancestors()]:
            figure.drop_tag()


def _heading_text(node) -> str:
    """A heading's words, with a line break inside it read as a space."""
    return " ".join(" ".join(node.itertext()).split())


def _formula_parts(document) -> set:
    """Everything inside a formula: its glyphs are not text of their own, the paragraph around them is."""
    parts = set()
    if not document.xpath(f'boolean({_TEX[1:]} | //*[local-name()="math"] | //script[contains(@type, "math/tex")])'):
        return parts
    for node in document.iter():
        if isinstance(node.tag, str) and node not in parts and math_source(node) is not None:
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
    return node.tag in _INLINE and not block(node)


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
        if NEGATIVE.search(f"{ancestor.get('id') or ''} {ancestor.get('class') or ''}"):
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
    return mount and not NEGATIVE.search(f"{node.get('id')} {node.get('class') or ''}")


def article_root(document):
    """The element with the most prose in and right under it, for a page Trafilatura cannot read."""
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
        if NEGATIVE.search(name):
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


def block(node) -> bool:
    """An element that stands on its own line, or any wrapper around one. A picture inside a span stays in its sentence."""
    if not isinstance(node.tag, str):
        return False
    if node.tag in _BLOCKS or node.tag in _SECTIONS:
        return True
    return any(isinstance(inner.tag, str) and inner.tag in _BLOCKS - {"img"} for inner in node.iterdescendants())


def holds_templates(node) -> bool:
    """A widget whose states wait in <template> elements next to its controls: the page shows one at a time,
    so it is read in the page and not as all of them at once."""
    children = [child for child in node if isinstance(child.tag, str)]
    return any(map(_inert, children)) and not all(map(_inert, children))


def _inert(node) -> bool:
    return node.tag == "template" or (len(node) > 0 and all(child.tag == "template" for child in node))


def live_figure(node) -> bool:
    """A figure the page draws itself, read as a crop of the live page with its caption. A figure of a picture,
    of an embedded video or of a pull quote reads as what it holds."""
    return node.tag == "figure" and not picture(node) and not node.xpath(".//iframe | ./blockquote")


def picture(node) -> bool:
    return bool(node.xpath(".//img")) and not widget(node)


def widget(node) -> bool:
    for candidate in node.iter():
        if not isinstance(candidate.tag, str) or math_source(candidate) is not None:
            continue
        if candidate.tag == "canvas":
            return True
        if candidate.tag == "script":
            return True
        if candidate.tag in {"div", "svg"} and candidate.get("id") and not " ".join(candidate.text_content().split()):
            return True
    return False


def contains_prose(node) -> bool:
    return any(isinstance(child.tag, str) and child.tag in PROSE for child in node.iter() if child is not node)


def selector(node) -> str:
    """A CSS selector that finds the element in the live page: its id, or its path of tags from the body."""
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


def math_source(node) -> tuple[str, bool] | None:
    """The TeX of a formula and whether it stands on its own line, for the element that is the whole formula."""
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

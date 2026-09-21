from __future__ import annotations

from lxml import html


def article_markdown(source: str) -> tuple[str, dict[str, str]]:
    document = html.fromstring(source)
    root = document.find(".//d-article")
    if root is None:
        root = document.find(".//article")
    if root is None:
        root = document.find(".//body")
    if root is None:
        root = document
    islands: dict[str, str] = {}
    blocks = [_block(child, islands) for child in root]
    text = "\n\n".join(block for block in blocks if block.strip())
    return text, islands


def _block(node, islands: dict[str, str]) -> str:
    if not isinstance(node.tag, str):
        return ""
    math = _math_source(node)
    if math is not None:
        source, display = math
        return f"$$\n{source}\n$$" if display else f"${source}$"
    if node.tag in {"script", "style", "d-front-matter"} or node.get("type") == "text/front-matter":
        return ""
    if _interactive(node):
        return _island(node, islands)
    tag = node.tag.lower()
    if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        return f"{'#' * int(tag[1])} {_inline(node)}"
    if tag in {"ul", "ol"}:
        return _list(node, ordered=tag == "ol")
    if tag == "blockquote":
        return "\n".join(f"> {line}" for line in _inline(node).splitlines())
    if tag == "pre":
        code = node.find("code")
        body = code.text_content() if code is not None else node.text_content()
        return f"```\n{body.rstrip()}\n```"
    if tag == "table":
        return _table(node)
    if tag == "img":
        return _image(node)
    if tag == "video":
        source = node.get("src") or ""
        nested = node.find("source")
        if not source and nested is not None:
            source = nested.get("src") or ""
        return f"```fnmn-video\n{source}\n```"
    if tag in {"p", "div", "section", "d-title", "figure", "figcaption"}:
        return _inline(node)
    return _inline(node)


def _interactive(node) -> bool:
    if _math_source(node) is not None:
        return False
    if node.tag in {"script", "canvas", "iframe"}:
        return True
    if isinstance(node.tag, str) and "-" in node.tag and node.tag not in {"d-front-matter", "d-title"}:
        return True
    return any(_interactive(child) for child in node if isinstance(child.tag, str))


def _island(node, islands: dict[str, str]) -> str:
    name = f"interactive/{len(islands) + 1}.html"
    fragment = html.tostring(node, encoding="unicode", method="html")
    islands[name] = (
        "<!doctype html><meta charset=\"utf-8\">"
        "<style>html,body{margin:0}</style>"
        f"{fragment}"
        "<script>function fnmnReportHeight(){parent.postMessage({kind:'fnmn-height',height:document.documentElement.scrollHeight},'*')}"
        "addEventListener('load',fnmnReportHeight);"
        "if(window.ResizeObserver)new ResizeObserver(fnmnReportHeight).observe(document.documentElement);</script>"
    )
    return f"```fnmn-interactive\n{name}\n```"


def _list(node, ordered: bool) -> str:
    lines = []
    for index, item in enumerate((child for child in node if child.tag == "li"), 1):
        marker = f"{index}." if ordered else "-"
        lines.append(f"{marker} {_inline(item)}")
    return "\n".join(lines)


def _table(node) -> str:
    rows = [child for child in node.iter("tr")]
    if not rows:
        return ""
    rendered = ["| " + " | ".join(_cells(row)) + " |" for row in rows]
    width = rendered[0].count("|") - 1
    rendered.insert(1, "| " + " | ".join("---" for _ in range(width)) + " |")
    return "\n".join(rendered)


def _cells(row) -> list[str]:
    return [_inline(cell).replace("|", "\\|") for cell in row if cell.tag in {"td", "th"}]


def _image(node) -> str:
    alt = node.get("alt") or ""
    src = node.get("src") or ""
    return f"![{alt}]({src})"


def _inline(node) -> str:
    parts: list[str] = []
    if node.text:
        parts.append(node.text)
    for child in node:
        if not isinstance(child.tag, str):
            if child.tail:
                parts.append(child.tail)
            continue
        if child.tag in {"em", "i"}:
            parts.append(f"*{_inline(child)}*")
        elif child.tag in {"strong", "b"}:
            parts.append(f"**{_inline(child)}**")
        elif child.tag == "code":
            parts.append(f"`{_inline(child)}`")
        elif child.tag == "a":
            parts.append(f"[{_inline(child)}]({child.get('href') or ''})")
        elif child.tag == "img":
            parts.append(_image(child))
        elif child.tag == "br":
            parts.append("\n")
        elif _math_source(child) is not None:
            source, display = _math_source(child)
            parts.append(f"$$\n{source}\n$$" if display else f"${source}$")
        else:
            parts.append(_inline(child))
        if child.tail:
            parts.append(child.tail)
    return "".join(parts).strip()


def _math_source(node) -> tuple[str, bool] | None:
    kind = node.get("type") or ""
    if node.tag == "script" and "math/tex" in kind:
        return (node.text or "").strip(), "display" in kind
    if node.tag == "math":
        annotation = node.find(".//annotation")
        if annotation is not None and annotation.text:
            return annotation.text.strip(), node.get("display") == "block"
    return None

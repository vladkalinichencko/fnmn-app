from __future__ import annotations

import json
import re
from urllib.parse import quote, urlparse

from lxml import html

from package import Document, Report
from web import Web

_STATUS = re.compile(r"/status(?:es)?/(\d+)")
_ARTICLE = re.compile(r"/i/article/(\d+)")
_TRAILING_LINK = re.compile(r"(?:\s*https://t\.co/\w+)+\s*$")


def read(url: str, web: Web, report: Report) -> Document:
    report("fetchingPage", None, None)
    path = urlparse(url).path
    if _ARTICLE.search(path):
        raise ValueError("X article text is not in a public fetch; oEmbed only returns a short post")
    if _STATUS.search(path) is None:
        raise ValueError("X link is not a single post")
    try:
        payload = json.loads(web.text("https://publish.x.com/oembed?url=" + quote(url, safe="")))
    except json.JSONDecodeError as error:
        raise ValueError("X did not return the post text") from error
    author = (payload.get("author_name") or "").strip() or None
    text = _post_text(payload.get("html") or "")
    if not text:
        raise ValueError("X did not return the post text")
    title = author or "X"
    return Document(f"# {title}\n\n{text}\n", title, author)


def _post_text(fragment: str) -> str:
    document = html.fromstring(f"<div>{fragment}</div>")
    paragraph = document.find(".//p")
    if paragraph is None:
        return ""
    for line_break in paragraph.findall(".//br"):
        line_break.tail = "\n" + (line_break.tail or "")
    return _TRAILING_LINK.sub("", paragraph.text_content()).strip()

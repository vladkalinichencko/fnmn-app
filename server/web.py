"""Everything the server reads from the internet goes through one Web value.

Adapters receive a Web and never import httpx or Chrome themselves, so tests
pass a Web made of plain functions.
"""

from __future__ import annotations

import re
from html import escape
from typing import Callable, NamedTuple

import httpx

import reader

_USER_AGENT = "FNMN/1.0 (https://github.com/vladkalinichencko/fnmn-app) article reader"


class Web(NamedTuple):
    text: Callable[[str], str]
    bytes: Callable[[str], bytes]
    page: Callable[[str], str]
    rendered: Callable[[str], str]


def _get(url: str) -> httpx.Response:
    response = httpx.get(url, follow_redirects=True, timeout=30, headers={"User-Agent": _USER_AGENT})
    response.raise_for_status()
    return response


def _page(url: str) -> str:
    response = _get(url)
    return with_base(response.text, str(response.url))


def _rendered(url: str) -> str:
    """Open the page in the reader browser on its own `web` profile: a real Chrome window that hides
    itself while it works, so a site that refuses headless Chrome sees the ordinary browser it is.
    A browser error page is no page: it raises like the network error it stands for."""
    with reader.job("web") as tab:
        tab.goto(url)
        tab.settle()
        status = tab.document_status()
        if status and status >= 400:
            raise OSError(f"browser got HTTP {status} for {url}")
        page = tab.html()
        if 'id="main-frame-error"' in page:
            raise OSError(f"the browser could not open {url}")
        return with_base(page, tab.url)


LIVE = Web(
    text=lambda url: _get(url).text,
    bytes=lambda url: _get(url).content,
    page=_page,
    rendered=_rendered,
)


def with_base(source: str, url: str) -> str:
    """Pin relative addresses to the address the page was finally served from."""
    if re.search(r"<base\s[^>]*href", source, re.I):
        return source
    tag = f'<base href="{escape(url, quote=True)}">'
    head = re.search(r"<head(?:\s[^>]*)?>", source, re.I)
    if head:
        return source[:head.end()] + tag + source[head.end():]
    declaration = re.match(r"\s*<\?xml[^>]*\?>", source)
    at = declaration.end() if declaration else 0
    return source[:at] + tag + source[at:]

"""The publisher of a web page: the page above it that stands for the blog, profile or site it belongs to,
and the name the site gives itself.

A page does not say where its publisher lives, so the nearest answer every site has is tried: the page's own
section (`/blog/` for `/blog/2026/post/`), then the front page. A section counts when it answers; a date
(`/2026/05/`) is never a section, since articles of one blog would then split by month. Nothing here may fail
an import: a site that cannot be asked has its front page for a publisher.
"""

from __future__ import annotations

import re
from urllib.parse import urlparse, urlunparse

from lxml import html

from web import Web

_SECTIONS_TRIED = 2
_OWNED_KINDS = {"huggingface.co": {"spaces", "datasets"}}
"""Hosts whose first path segment names a kind of page and the second its owner, as in `/spaces/owner/name`:
the owner's page is the publisher, not the list of every owner's pages."""
_NAMES = (
    "//meta[@property='og:site_name']/@content",
    "//meta[@name='application-name']/@content",
)


def publisher_of(url: str, source: str, web: Web) -> dict | None:
    """`{"name": ..., "homepage": ...}` for the app's `PageSource`; the name is left out when the page has none."""
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return None
    owner = _owner(parsed)
    if owner:
        return {"homepage": _address(parsed, f"/{owner}"), "name": owner}
    publisher = {"homepage": homepage_of(parsed, web)}
    name = site_name(source)
    if name:
        publisher["name"] = name
    return publisher


def site_name(source: str) -> str | None:
    try:
        document = html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))
    except Exception:
        return None
    for query in _NAMES:
        for value in document.xpath(query):
            name = " ".join(value.split())
            if name:
                return name
    return None


def _owner(parsed) -> str | None:
    segments = [part for part in parsed.path.split("/") if part]
    kinds = _OWNED_KINDS.get((parsed.hostname or "").lower().removeprefix("www."), set())
    return segments[1] if len(segments) > 2 and segments[0] in kinds else None


def homepage_of(parsed, web: Web) -> str:
    segments = [part for part in parsed.path.split("/") if part]
    sections = [segments[:depth] for depth in range(1, len(segments)) if not segments[depth - 1].isdigit()]
    for section in sections[:_SECTIONS_TRIED]:
        address = _address(parsed, "/" + "/".join(section) + "/")
        if _answers(address, web):
            return address
    return _address(parsed, "/")


def _address(parsed, path: str) -> str:
    return urlunparse((parsed.scheme, parsed.netloc, path, "", "", ""))


def _answers(address: str, web: Web) -> bool:
    try:
        return bool(web.text(address).strip())
    except Exception:
        return False

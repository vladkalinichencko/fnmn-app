"""A web page as one Markdown document with its pictures and videos as files."""

from __future__ import annotations

import re
from urllib.parse import urldefrag

from lxml import html

from adapters.html_markdown import article_markdown
from package import Document, ImportFailure, Report
from publisher import publisher_of
from sources import source_kind
from web import Web

_FRAME_DEPTH = 2
"""A page inside a frame inside a frame is still followed; deeper than that it is an embed, not an article."""


def read(url: str, web: Web, report: Report) -> Document:
    report("fetchingPage", None, None)
    source, markdown, assets = _readable_page(url, web)
    content = document(source, markdown, assets, web, report)
    content.publisher = publisher_of(url, source, web)
    return content


def document(source: str, markdown: str, assets: dict[str, str], web: Web, report: Report) -> Document:
    """A page already turned into Markdown, with the pictures and videos it names; one the web no longer
    serves leaves the text."""
    report("fetchingAssets", 0, len(assets))
    files: dict[str, bytes] = {}
    for done, (path, asset_url) in enumerate(assets.items(), 1):
        try:
            files[path] = web.bytes(asset_url)
        except Exception as error:
            markdown = _without_asset(markdown, path, error)
        report("fetchingAssets", done, len(assets))
    document = html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))
    title = document.xpath("string(//title)").strip() or None
    author = next(iter(document.xpath("//meta[@name='author']/@content")), None)
    return Document(markdown, title, author, files)


def _readable_page(url: str, web: Web, depth: int = 0) -> tuple[str, str, dict[str, str]]:
    """Read the page as Chrome shows it once its scripts ran, since many sites send only a shell, or a section's
    blurb, before that; a page Chrome cannot open is read over plain HTTP. A page that is only a frame around
    another page is that other page."""
    try:
        source = web.rendered(url)
    except Exception as refusal:
        try:
            source = web.page(url)
        except Exception as error:
            raise ImportFailure("fetchingPage", f"Chrome: {refusal}; {error}") from error
    markdown, assets = article_markdown(source, url)
    if not _has_prose(markdown) and (framed := _inside_frame(source, url, web, depth)):
        return framed
    return source, markdown, assets


def _inside_frame(source: str, url: str, web: Web, depth: int) -> tuple[str, str, dict[str, str]] | None:
    """What a Hugging Face Space or any other page that holds its article in one frame is made of: the frame's
    page, read as a page of its own, so its pictures and live figures are found at the address they come from."""
    if depth >= _FRAME_DEPTH:
        return None
    address = _page_frame(source, url)
    if address is None:
        return None
    try:
        return _readable_page(address, web, depth + 1)
    except ImportFailure:
        return None


def _page_frame(source: str, url: str) -> str | None:
    """The first frame that shows another web page to the reader: not a hidden tracker, not a video player."""
    document = html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1), base_url=url)
    document.make_links_absolute(url, resolve_base_href=True, handle_failures="ignore")
    for frame in document.iter("iframe"):
        address = (frame.get("src") or "").strip()
        if source_kind(address) != "web" or urldefrag(address).url == urldefrag(url).url:
            continue
        if not _hidden(frame):
            return address
    return None


def _hidden(frame) -> bool:
    for node in (frame, *frame.iterancestors()):
        style = re.sub(r"\s+", "", (node.get("style") or "").lower())
        if "display:none" in style or "visibility:hidden" in style or node.get("hidden") is not None:
            return True
        if node.get("aria-hidden") == "true":
            return True
    return {frame.get("width"), frame.get("height")} & {"0", "1"} != set()


def _has_prose(markdown: str) -> bool:
    text = re.sub(r"```.*?```", "", markdown, flags=re.S)
    return any(line.strip() and not line.startswith("#") for line in text.splitlines())


def _without_asset(markdown: str, path: str, error: Exception) -> str:
    """A picture or video the site no longer serves leaves the text; anything else stops the import."""
    video = f"```fnmn-video\n{path}\n```"
    if video in markdown:
        return markdown.replace(video, "")
    image = rf"!\[[^\]]*\]\({re.escape(path)}\)"
    if re.search(image, markdown):
        return re.sub(image, "", markdown)
    raise ImportFailure("fetchingAssets", str(error)) from error

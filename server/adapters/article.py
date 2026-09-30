"""A web page as one Markdown document with its pictures and videos as files."""

from __future__ import annotations

import re

from lxml import html

from adapters.html_markdown import article_markdown
from package import Document, ImportFailure, Report
from web import Web


def read(url: str, web: Web, report: Report) -> Document:
    report("fetchingPage", None, None)
    source, markdown, assets = _readable_page(url, web)
    return document(source, markdown, assets, web, report)


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


def _readable_page(url: str, web: Web) -> tuple[str, str, dict[str, str]]:
    """Read the plain HTTP page; open it in Chrome when the site refuses or sends a shell for its scripts."""
    try:
        source = web.page(url)
        markdown, assets = article_markdown(source, url)
        if _has_prose(markdown):
            return source, markdown, assets
        refusal = "page has no readable text before its scripts run"
    except Exception as error:
        refusal = str(error)
    try:
        source = web.rendered(url)
        markdown, assets = article_markdown(source, url)
    except Exception as error:
        raise ImportFailure("fetchingPage", f"{refusal}; Chrome: {error}") from error
    return source, markdown, assets


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

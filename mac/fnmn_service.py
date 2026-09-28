from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

from xml.sax.saxutils import escape

from adapter_arxiv import arxiv_markdown
from adapter_chatgpt import chatgpt_markdown
from adapter_x import x_markdown
from adapter_youtube import youtube_package_live
from html_markdown import article_markdown, with_base
from page_browser import rendered_page
from sources import NAMES, source_kind

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException
from lxml import html
from pydantic import BaseModel


class ArticleRequest(BaseModel):
    url: str
    folders: list[str] = []


def stable_id(prefix: str, value: str) -> str:
    return f"{prefix}:{hashlib.sha256(value.encode()).hexdigest()[:24]}"


class ImportFailure(Exception):
    def __init__(self, phase: str, reason: str):
        self.phase = phase
        super().__init__(f"{phase}: {reason}")


def import_web_article(
    url: str,
    fetch_text: Callable[[str], str],
    fetch_bytes: Callable[[str], bytes],
    folders: list[str] | None = None,
    render_text: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ImportFailure("fetchingPage", "article URL must be absolute HTTP or HTTPS")
    source, markdown, assets = _read_article(url, fetch_text, render_text)
    files: dict[str, str] = {}
    try:
        for path, asset_url in assets.items():
            try:
                files[path] = base64.b64encode(fetch_bytes(asset_url)).decode("ascii")
            except Exception:
                image = rf"!\[[^\]]*\]\({re.escape(path)}\)"
                video = f"```fnmn-video\n{path}\n```"
                if video in markdown:
                    markdown = markdown.replace(video, "")
                elif re.search(image, markdown):
                    markdown = re.sub(image, "", markdown)
                else:
                    raise
    except Exception as error:
        raise ImportFailure("fetchingAssets", str(error)) from error
    try:
        package = _markdown_package(url, source, markdown, folders or [])
    except Exception as error:
        raise ImportFailure("saving", str(error)) from error
    package["files"] = files
    return package


def _read_article(
    url: str,
    fetch_text: Callable[[str], str],
    render_text: Callable[[str], str] | None,
) -> tuple[str, str, dict[str, str]]:
    try:
        source = fetch_text(url)
        markdown, assets = article_markdown(source, url)
        if _has_prose(markdown) or render_text is None:
            return source, markdown, assets
        refusal = "page has no readable text before its scripts run"
    except Exception as error:
        if render_text is None:
            raise ImportFailure("fetchingPage", str(error)) from error
        refusal = str(error)
    try:
        source = render_text(url)
        markdown, assets = article_markdown(source, url)
    except Exception as error:
        raise ImportFailure("fetchingPage", f"{refusal}; Chrome: {error}") from error
    return source, markdown, assets


def _has_prose(markdown: str) -> bool:
    text = re.sub(r"```.*?```", "", markdown, flags=re.S)
    return any(line.strip() and not line.startswith("#") for line in text.splitlines())


def import_link(
    url: str,
    fetch_text: Callable[[str], str],
    fetch_bytes: Callable[[str], bytes],
    folders: list[str] | None = None,
    render_text: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    kind = source_kind(url)
    if kind is None:
        raise ImportFailure("fetchingPage", "article URL must be absolute HTTP or HTTPS")
    if kind in {"web", "substack"}:
        return import_web_article(url, fetch_text, fetch_bytes, folders, render_text)
    if kind == "youtube":
        try:
            return youtube_package_live(url, folders or [])
        except ImportFailure:
            raise
        except ValueError as error:
            raise ImportFailure("saving", str(error)) from error
        except Exception as error:
            raise ImportFailure("fetchingPage", str(error)) from error
    try:
        if kind == "arxiv":
            markdown, author, files = arxiv_markdown(url, fetch_text, fetch_bytes)
        elif kind == "x":
            markdown, author, files = x_markdown(url, fetch_text)
        elif kind == "chatgpt":
            markdown, author, files = chatgpt_markdown(url, fetch_text)
        else:
            raise ImportFailure("saving", f"{NAMES[kind]} is recognized, but the Mac service does not prepare it yet.")
    except ImportFailure:
        raise
    except ValueError as error:
        raise ImportFailure("saving", str(error)) from error
    except Exception as error:
        raise ImportFailure("fetchingPage", str(error)) from error
    try:
        return _text_package(url, markdown, author, files, folders or [])
    except Exception as error:
        raise ImportFailure("saving", str(error)) from error


def _text_package(
    url: str,
    markdown: str,
    author: str | None,
    files: dict[str, bytes],
    folders: list[str],
) -> dict[str, Any]:
    author_tag = ""
    if author:
        safe_author = escape(author).replace('"', "&quot;")
        author_tag = f'<meta name="author" content="{safe_author}">'
    source = f"<html><head><title></title>{author_tag}</head><body></body></html>"
    package = _markdown_package(url, source, markdown, folders)
    package["files"] = {path: base64.b64encode(blob).decode("ascii") for path, blob in files.items()}
    return package


def _markdown_package(url: str, source: str, markdown: str, folders: list[str]) -> dict[str, Any]:
    if not markdown.strip():
        raise ValueError("article markdown is empty")
    document = html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))
    heading = next((line[2:].strip() for line in markdown.splitlines() if line.startswith("# ")), "")
    title_values = document.xpath("string(//title)")
    title = heading or (title_values or "").strip() or urlparse(url).netloc
    author_values = document.xpath("//meta[@name='author']/@content")
    return {
        "version": 1,
        "material": {
            "id": stable_id("article", url),
            "kind": "article",
            "title": title,
            "sourceURL": url,
            "byline": next(iter(author_values), None),
        },
        "sections": [],
        "blocks": [],
        "folders": folders,
        "body": markdown,
    }


_USER_AGENT = "FNMN/1.0 (https://github.com/vladkalinichencko/fnmn-app) article reader"


def _http_get(url: str) -> httpx.Response:
    response = httpx.get(url, follow_redirects=True, timeout=30, headers={"User-Agent": _USER_AGENT})
    response.raise_for_status()
    return response


def _page_source(url: str) -> str:
    response = _http_get(url)
    return with_base(response.text, str(response.url))


def require_token(authorization: str | None = Header(default=None)) -> None:
    token = os.environ.get("FNMN_TOKEN")
    if not token:
        raise HTTPException(503, "FNMN_TOKEN is not configured")
    if authorization != f"Bearer {token}":
        raise HTTPException(401, "invalid bearer token")


app = FastAPI(title="FNMN article service")


@app.get("/health", dependencies=[Depends(require_token)])
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/articles", dependencies=[Depends(require_token)])
def article(request: ArticleRequest) -> dict[str, Any]:
    try:
        return import_link(request.url, _page_source, lambda page: _http_get(page).content, request.folders, rendered_page)
    except ImportFailure as error:
        raise HTTPException(422, str(error)) from error


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare one explicitly supplied article link for FNMN")
    parser.add_argument("url")
    parser.add_argument("--folder", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    package = import_link(args.url, _page_source, lambda page: _http_get(page).content, args.folder, rendered_page)
    args.output.write_text(json.dumps(package, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

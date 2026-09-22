from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urljoin, urlparse

from html_markdown import article_markdown

import httpx
import trafilatura
from fastapi import Depends, FastAPI, Header, HTTPException
from lxml import html
from pydantic import BaseModel


class ArticleRequest(BaseModel):
    url: str
    folders: list[str] = []


def stable_id(prefix: str, value: str) -> str:
    return f"{prefix}:{hashlib.sha256(value.encode()).hexdigest()[:24]}"


def prepare_article(url: str, source_html: str, folders: list[str] | None = None) -> dict[str, Any]:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("article URL must be absolute HTTP or HTTPS")
    extracted = trafilatura.extract(
        source_html,
        url=url,
        output_format="html",
        include_images=True,
        include_links=True,
        include_formatting=True,
        with_metadata=True,
    )
    if not extracted:
        raise ValueError("article extractor found no readable content")
    extracted_document = html.fromstring(extracted)
    source_document = html.fromstring(source_html)
    article_elements = source_document.xpath("//article")
    document = article_elements[0] if article_elements else extracted_document
    title_values = source_document.xpath("string(//title)")
    extracted_titles = extracted_document.xpath("//meta[@name='title']/@content")
    title = (title_values or next(iter(extracted_titles), None) or parsed.netloc).strip()
    author_values = source_document.xpath("//meta[@name='author']/@content")
    byline = next(iter(author_values), None)
    material_id = stable_id("article", url)
    sections: list[dict[str, Any]] = []
    blocks: list[dict[str, Any]] = []
    section_stack: list[tuple[int, str]] = []
    current_section: str | None = None

    nodes = document.xpath(".//h1|.//h2|.//h3|.//h4|.//h5|.//h6|.//p|.//pre|.//blockquote|.//ul|.//ol|.//table|.//figure|.//img|.//math|.//video|.//iframe")
    for node in nodes:
        tag = node.tag.lower()
        if any(parent.tag in {"figure", "p", "ul", "ol", "table"} for parent in node.iterancestors()):
            continue
        text = " ".join(node.text_content().split())
        if tag.startswith("h") and tag[1:].isdigit():
            if not text:
                continue
            level = int(tag[1:])
            block_id = stable_id("block", f"{url}:{len(blocks)}:{text}")
            section_id = stable_id("section", f"{url}:{len(sections)}:{text}")
            while section_stack and section_stack[-1][0] >= level:
                section_stack.pop()
            parent_id = section_stack[-1][1] if section_stack else None
            sections.append({"id": section_id, "parentID": parent_id, "title": text, "level": level, "firstBlockID": block_id})
            section_stack.append((level, section_id))
            current_section = section_id
            kind = "heading"
        elif tag in {"img", "figure"}:
            image = node if tag == "img" else next(iter(node.xpath(".//img")), None)
            if image is None or not image.get("src"):
                continue
            image.set("src", urljoin(url, image.get("src")))
            block_id = stable_id("block", f"{url}:{len(blocks)}:{image.get('src')}")
            kind = "image"
            media_url = image.get("src")
        elif tag in {"video", "iframe"}:
            if not node.get("src"):
                continue
            node.set("src", urljoin(url, node.get("src")))
            block_id = stable_id("block", f"{url}:{len(blocks)}:{node.get('src')}")
            kind = "video"
            media_url = node.get("src")
        elif tag == "math":
            block_id = stable_id("block", f"{url}:{len(blocks)}:{text}")
            kind = "formula"
        else:
            if not text:
                continue
            block_id = stable_id("block", f"{url}:{len(blocks)}:{text}")
            kind = "paragraph"
        if tag not in {"img", "figure", "video", "iframe"}:
            media_url = None
        fragment = node.get("id")
        rendered = html.tostring(node, encoding="unicode", method="html")
        blocks.append({
            "id": block_id,
            "sectionID": current_section,
            "kind": kind,
            "html": rendered,
            "sourceFragment": f"#{fragment}" if fragment else None,
            "mediaURL": media_url,
            "startSeconds": None,
        })
    if not blocks:
        raise ValueError("article extractor produced no supported blocks")
    if not sections:
        sections.append({"id": "root", "parentID": None, "title": title, "level": 1, "firstBlockID": blocks[0]["id"]})
        for block in blocks:
            block["sectionID"] = "root"
    return {
        "version": 1,
        "material": {"id": material_id, "kind": "article", "title": title, "sourceURL": url, "byline": byline},
        "sections": sections,
        "blocks": blocks,
        "folders": folders or [],
    }


class ImportFailure(Exception):
    def __init__(self, phase: str, reason: str):
        self.phase = phase
        super().__init__(f"{phase}: {reason}")


def import_web_article(
    url: str,
    fetch_text: Callable[[str], str],
    fetch_bytes: Callable[[str], bytes],
    folders: list[str] | None = None,
) -> dict[str, Any]:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ImportFailure("fetchingPage", "article URL must be absolute HTTP or HTTPS")
    try:
        source = fetch_text(url)
        markdown, assets = article_markdown(source, url)
    except ImportFailure:
        raise
    except Exception as error:
        raise ImportFailure("fetchingPage", str(error)) from error
    files: dict[str, str] = {}
    try:
        for path, asset_url in assets.items():
            files[path] = base64.b64encode(fetch_bytes(asset_url)).decode("ascii")
    except Exception as error:
        raise ImportFailure("fetchingAssets", str(error)) from error
    try:
        package = _markdown_package(url, source, markdown, folders or [])
    except Exception as error:
        raise ImportFailure("saving", str(error)) from error
    package["files"] = files
    return package


def _markdown_package(url: str, source: str, markdown: str, folders: list[str]) -> dict[str, Any]:
    document = html.fromstring(source)
    heading = next((line[2:].strip() for line in markdown.splitlines() if line.startswith("# ")), "")
    title_values = document.xpath("string(//title)")
    title = heading or (title_values or "").strip() or urlparse(url).netloc
    author_values = document.xpath("//meta[@name='author']/@content")
    sections, blocks = _outline(url, markdown, title)
    return {
        "version": 1,
        "material": {
            "id": stable_id("article", url),
            "kind": "article",
            "title": title,
            "sourceURL": url,
            "byline": next(iter(author_values), None),
        },
        "sections": sections,
        "blocks": blocks,
        "folders": folders,
        "body": markdown,
    }


def _outline(url: str, markdown: str, title: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    sections: list[dict[str, Any]] = []
    blocks: list[dict[str, Any]] = []
    section_id: str | None = None
    for chunk in re.split(r"\n\n+", markdown.strip()):
        if chunk.startswith("```") or chunk.startswith("!["):
            continue
        heading = re.fullmatch(r"(#{1,6})[ \t]+(\S.*)", chunk.strip())
        if heading:
            text = heading.group(2).strip()
            level = len(heading.group(1))
        else:
            text = " ".join(chunk.split())
            level = 0
        if not text:
            continue
        block_id = stable_id("block", f"{url}:{len(blocks)}:{text}")
        if level:
            section_id = stable_id("section", f"{url}:{len(sections)}:{text}")
            sections.append({"id": section_id, "parentID": None, "title": text, "level": level, "firstBlockID": block_id})
            kind = "heading"
        else:
            kind = "paragraph"
        blocks.append({
            "id": block_id,
            "sectionID": section_id,
            "kind": kind,
            "html": text,
            "sourceFragment": None,
            "mediaURL": None,
            "startSeconds": None,
        })
    if not blocks:
        block_id = stable_id("block", url)
        section_id = stable_id("section", f"{url}:{title}")
        sections.append({"id": section_id, "parentID": None, "title": title, "level": 1, "firstBlockID": block_id})
        blocks.append({
            "id": block_id,
            "sectionID": section_id,
            "kind": "paragraph",
            "html": title,
            "sourceFragment": None,
            "mediaURL": None,
            "startSeconds": None,
        })
    if not sections:
        sections.append({"id": "root", "parentID": None, "title": title, "level": 1, "firstBlockID": blocks[0]["id"]})
        for block in blocks:
            block["sectionID"] = "root"
    return sections, blocks


def _http_get(url: str) -> httpx.Response:
    response = httpx.get(url, follow_redirects=True, timeout=30, headers={"User-Agent": "FNMN/1.0 article reader"})
    response.raise_for_status()
    return response


def require_token(authorization: str | None = Header(default=None)) -> None:
    token = os.environ.get("FNMN_TOKEN")
    if not token:
        raise HTTPException(503, "FNMN_TOKEN is not configured")
    if authorization != f"Bearer {token}":
        raise HTTPException(401, "invalid bearer token")


app = FastAPI(title="FNMN article service")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/articles", dependencies=[Depends(require_token)])
def article(request: ArticleRequest) -> dict[str, Any]:
    try:
        return import_web_article(request.url, lambda page: _http_get(page).text, lambda page: _http_get(page).content, request.folders)
    except ImportFailure as error:
        raise HTTPException(422, str(error)) from error


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare one explicitly supplied web article for FNMN")
    parser.add_argument("url")
    parser.add_argument("--folder", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    package = import_web_article(args.url, lambda page: _http_get(page).text, lambda page: _http_get(page).content, args.folder)
    args.output.write_text(json.dumps(package, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse

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
        parsed = urlparse(request.url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("article URL must be absolute HTTP or HTTPS")
        response = httpx.get(request.url, follow_redirects=True, timeout=30, headers={"User-Agent": "FNMN/1.0 article reader"})
        response.raise_for_status()
        return prepare_article(request.url, response.text, request.folders)
    except (ValueError, httpx.HTTPError) as error:
        raise HTTPException(422, str(error)) from error


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare one explicitly supplied web article for FNMN")
    parser.add_argument("url")
    parser.add_argument("--folder", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    response = httpx.get(args.url, follow_redirects=True, timeout=30, headers={"User-Agent": "FNMN/1.0 article reader"})
    response.raise_for_status()
    args.output.write_text(json.dumps(prepare_article(args.url, response.text, args.folder), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

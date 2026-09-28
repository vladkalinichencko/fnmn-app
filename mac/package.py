"""The adapter contract and the one delivery format FNMN imports.

Every adapter is `read(url, web, report) -> Document | Video`. It reports its
stage through `report` and stops with ImportFailure. `package` turns either
content into the JSON the app decodes as `ImportPackage`.
"""

from __future__ import annotations

import base64
import hashlib
from dataclasses import dataclass, field
from typing import Callable
from urllib.parse import urlparse


Report = Callable[[str, int | None, int | None], None]
"""stage, done, total: e.g. ("ocr", 40, 380) or ("fetchingPage", None, None)."""


class ImportFailure(Exception):
    def __init__(self, phase: str, reason: str):
        self.phase = phase
        super().__init__(f"{phase}: {reason}")


@dataclass
class Document:
    markdown: str
    title: str | None = None
    author: str | None = None
    files: dict[str, bytes] = field(default_factory=dict)


@dataclass
class Video:
    video_id: str
    title: str
    author: str | None = None
    cues: list[tuple[float, str]] = field(default_factory=list)


def package(url: str, content: Document | Video, folders: list[str]) -> dict:
    if isinstance(content, Video):
        return _video_package(content, folders)
    return _document_package(url, content, folders)


def stable_id(prefix: str, value: str) -> str:
    return f"{prefix}:{hashlib.sha256(value.encode()).hexdigest()[:24]}"


def _document_package(url: str, document: Document, folders: list[str]) -> dict:
    if not document.markdown.strip():
        raise ValueError("article markdown is empty")
    heading = next((line[2:].strip() for line in document.markdown.splitlines() if line.startswith("# ")), "")
    return {
        "version": 1,
        "material": {
            "id": stable_id("article", url),
            "kind": "article",
            "title": heading or document.title or urlparse(url).netloc,
            "sourceURL": url,
            "byline": document.author,
        },
        "sections": [],
        "blocks": [],
        "folders": folders,
        "body": document.markdown,
        "files": {path: base64.b64encode(blob).decode("ascii") for path, blob in document.files.items()},
    }


def _video_package(video: Video, folders: list[str]) -> dict:
    material_id = f"youtube:{video.video_id}"
    section_id = stable_id("section", f"{material_id}:video")
    player_id = stable_id("block", f"{material_id}:video")
    blocks = [_block(player_id, section_id, "video", video.title, f"https://www.youtube.com/embed/{video.video_id}", 0.0)]
    for index, (start, text) in enumerate(video.cues):
        cue_id = stable_id("block", f"{material_id}:cue:{index}:{start}:{text}")
        blocks.append(_block(cue_id, section_id, "transcript", text, None, start))
    return {
        "version": 1,
        "material": {
            "id": material_id,
            "kind": "video",
            "title": video.title,
            "sourceURL": f"https://www.youtube.com/watch?v={video.video_id}",
            "byline": video.author,
        },
        "sections": [{"id": section_id, "parentID": None, "title": video.title, "level": 1, "firstBlockID": player_id}],
        "blocks": blocks,
        "folders": folders,
        "body": "\n\n".join(text for _, text in video.cues),
        "files": {},
    }


def _block(block_id: str, section_id: str, kind: str, text: str, media_url: str | None, start: float) -> dict:
    return {
        "id": block_id,
        "sectionID": section_id,
        "kind": kind,
        "html": text,
        "sourceFragment": None,
        "mediaURL": media_url,
        "startSeconds": start,
    }

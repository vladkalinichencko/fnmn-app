"""The adapter contract and the one delivery format FNMN imports.

Every adapter is `read(url, web, report) -> Document | Video`. It reports its
stage through `report` and stops with ImportFailure. `package` turns either
content into a Delivery: the JSON the app decodes as `ImportPackage` and the
files its Markdown names. `write_delivery` lays a delivery out as one
uncompressed tar, `package.json` first, which the app reads in one pass.
"""

from __future__ import annotations

import filecmp
import hashlib
import io
import json
import shutil
import tarfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable
from urllib.parse import urlparse

from markdown import first_heading, normalize, page_title


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


@dataclass
class Delivery:
    package: dict
    """The app's `ImportPackage`."""
    files: dict[str, bytes] = field(default_factory=dict)
    """Relative path in the Markdown -> the file's bytes."""


PACKAGE_NAME = "package.json"


def package(url: str, content: Document | Video, folders: list[str]) -> Delivery:
    if isinstance(content, Video):
        return Delivery(_video_package(content, folders))
    fallback = urlparse(url).netloc
    return Delivery(_document_package(stable_id("article", url), url, content, folders, fallback), content.files)


def file_id(data: bytes) -> str:
    """A material made from a file is known by the file's bytes, so the same file sent again replaces it.
    The phone names a file it keeps without the Mac the same way."""
    return "file:" + hashlib.sha256(data).hexdigest()


def package_file(name: str, data: bytes, document: Document) -> Delivery:
    """A material made from a file has no page: its original is the file, which the phone keeps in `originals/`."""
    return Delivery(_document_package(file_id(data), None, document, [], Path(name).stem or name), document.files)


def file_delivery(name: str, data: bytes) -> Delivery:
    """What a file becomes when nothing could be made of it: a material with no text whose original is the file."""
    return Delivery({
        "version": 1,
        "material": {"id": file_id(data), "kind": "link", "title": Path(name).stem or name},
        "sections": [],
        "blocks": [],
        "folders": [],
    })


def link_delivery(url: str, title: str | None, folders: list[str]) -> Delivery:
    """What a link becomes when nothing could be made of it: a material with no text whose original is the
    page. Its id is the one the app has always given a saved link, so its albums and marks stay with it."""
    parsed = urlparse(url)
    return Delivery({
        "version": 1,
        "material": {
            "id": f"link:{url}",
            "kind": "link",
            "title": title or (parsed.netloc + parsed.path).rstrip("/") or url,
            "sourceURL": url,
        },
        "sections": [],
        "blocks": [],
        "folders": folders,
    })


def book_delivery(folder: Path) -> Delivery:
    """A book the PDF pipeline exported (`content.md`, `metadata.json`, `assets/`) as a delivery like any other:
    its text is the body, whose headings are its table of contents, and its authors the byline. It has no page
    on the web: its original is the PDF, kept beside the delivery. The id stays `book:<source name>`, as the app
    has always called the book."""
    metadata = json.loads((folder / "metadata.json").read_text(encoding="utf-8"))
    body = (folder / metadata["content_file"]).read_text(encoding="utf-8")
    files = {
        path.relative_to(folder).as_posix(): path.read_bytes()
        for path in sorted((folder / metadata["assets_directory"]).rglob("*"))
        if path.is_file() and not path.name.startswith(".")
    }
    return Delivery(
        {
            "version": 1,
            "material": {
                "id": f"book:{metadata['source_name']}",
                "kind": "book",
                "title": metadata["title"],
                "byline": ", ".join(metadata.get("authors", [])) or None,
            },
            "sections": [],
            "blocks": [],
            "folders": [],
            "body": body,
        },
        files,
    )


def delivery_name(material_id: str) -> str:
    """The archive's name in `deliveries/` for a material that has no link of its own; the app names the
    materials it adds the same way."""
    return hashlib.sha256(material_id.encode()).hexdigest() + ".tar"


def place_original(library: Path, delivery: str, original: Path) -> None:
    """The file a material was made from goes to `originals/`, named like its delivery with its own extension,
    where the app finds it for Open Original."""
    path = library / "originals" / (Path(delivery).stem + original.suffix.lower())
    path.parent.mkdir(parents=True, exist_ok=True)
    incoming = path.with_name(path.name + ".incoming")
    shutil.copyfile(original, incoming)
    replace_if_changed(incoming, path)


def write_delivery(path: Path, delivery: Delivery) -> None:
    """USTAR, so the app's reader needs no PAX headers; a path too long for it fails here."""
    path.parent.mkdir(parents=True, exist_ok=True)
    incoming = path.with_suffix(".incoming")
    with tarfile.open(incoming, "w", format=tarfile.USTAR_FORMAT) as archive:
        _add(archive, PACKAGE_NAME, json.dumps(delivery.package, ensure_ascii=False).encode())
        for name, blob in delivery.files.items():
            _add(archive, name, blob)
    replace_if_changed(incoming, path)


def write_if_changed(path: Path, blob: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    incoming = path.with_name(path.name + ".incoming")
    incoming.write_bytes(blob)
    replace_if_changed(incoming, path)


def replace_if_changed(incoming: Path, path: Path) -> None:
    """The library lives in iCloud Drive: a file written beside its place and renamed over it is a new version
    of the same file, where writing over a file iCloud is still syncing leaves a numbered copy. An unchanged
    file is not touched at all, so iCloud uploads only what changed."""
    if path.exists() and filecmp.cmp(incoming, path, shallow=False):
        incoming.unlink()
    else:
        incoming.replace(path)


def read_delivery(path: Path) -> Delivery:
    with tarfile.open(path, "r:") as archive:
        members = archive.getmembers()
        if not members or members[0].name != PACKAGE_NAME:
            raise ValueError(f"{path.name} does not start with {PACKAGE_NAME}")
        package = json.loads(archive.extractfile(members[0]).read())
        files = {member.name: archive.extractfile(member).read() for member in members[1:]}
    return Delivery(package, files)


def _add(archive: tarfile.TarFile, name: str, blob: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(blob)
    info.mode = 0o644
    archive.addfile(info, io.BytesIO(blob))


def stable_id(prefix: str, value: str) -> str:
    return f"{prefix}:{hashlib.sha256(value.encode()).hexdigest()[:24]}"


def _document_package(material_id: str, url: str | None, document: Document, folders: list[str], fallback: str) -> dict:
    if not document.markdown.strip():
        raise ValueError("article markdown is empty")
    body = normalize(document.markdown)
    heading = first_heading(body) or (document.title and page_title(document.title))
    return {
        "version": 1,
        "material": {
            "id": material_id,
            "kind": "article",
            "title": heading or fallback,
            "sourceURL": url,
            "byline": document.author,
        },
        "sections": [],
        "blocks": [],
        "folders": folders,
        "body": body,
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

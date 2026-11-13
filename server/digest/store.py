"""The post store on the Mac: one append-only log of every post the monitor collected, the media files it
downloaded, and the log of the digests already built. A post names its media by a path relative to `out/`,
so a build copies the files into the delivery without downloading anything again.

Posted times are ISO 8601 in UTC with a trailing `Z`, the same shape `DigestPackage` decodes on the phone.
"""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"


def iso(moment: datetime) -> str:
    """The one way a time is written to the phone: UTC to the second, with `Z`."""
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class Post:
    id: str
    network: str
    source: str
    author: dict
    permalink: str
    posted_at: str
    text: str | None = None
    media: list[dict] = field(default_factory=list)
    video: dict | None = None
    context: dict | None = None
    comments: list[dict] = field(default_factory=list)
    stats: dict | None = None
    folders: list[str] = field(default_factory=list)
    media_errors: int = 0

    def __post_init__(self) -> None:
        """Instagram's `og:title` is `Name on Instagram: "caption"`; the card wants only the name, and
        `@handle` stands in for a missing display name. Rows written before the fix carry the raw title."""
        if self.network != "instagram":
            return
        raw = self.author.get("name") or ""
        match = re.match(r"^(.*?) on Instagram\b", raw)
        name = (match.group(1) if match else raw).strip()
        if not name or name.startswith("@"):
            name = self.author.get("handle") or name
        self.author = {**self.author, "name": name}


def wire(post: Post) -> dict:
    """A post as the phone's `DigestPackage.Post` decodes it: camelCase keys, one level of context."""
    return {
        "id": post.id,
        "network": post.network,
        "author": post.author,
        "permalink": post.permalink,
        "postedAt": post.posted_at,
        "text": post.text,
        "media": post.media,
        "video": post.video,
        "context": wire_context(post.context),
        "comments": post.comments,
        "stats": post.stats,
        "folders": post.folders,
        "mediaErrors": post.media_errors,
    }


def wire_context(context: dict | None) -> dict | None:
    if context is None:
        return None
    post = context.get("post")
    return {
        "kind": context["kind"],
        "post": None if post is None else {
            "id": post["id"],
            "network": post["network"],
            "author": post["author"],
            "permalink": post["permalink"],
            "postedAt": post.get("posted_at") or post.get("postedAt"),
            "text": post.get("text"),
            "media": post.get("media", []),
            "video": post.get("video"),
            "stats": post.get("stats"),
        },
    }


class Store:
    def __init__(self, root: Path = OUT):
        self.root = root
        self.posts_file = root / "posts.jsonl"
        self.builds_file = root / "builds.jsonl"
        self.sources_file = root / "sources.json"
        self.media_dir = root / "media"
        self._sig_cache: dict[str, tuple[str, frozenset[str]]] = {}

    def posts(self) -> list[Post]:
        """Every collected post, oldest first. A run that died mid-line leaves a torn tail, which is skipped;
        the next run appends after it."""
        if not self.posts_file.exists():
            return []
        posts = []
        for line in self.posts_file.read_text(encoding="utf-8").splitlines():
            try:
                posts.append(Post(**json.loads(line)))
            except (json.JSONDecodeError, TypeError):
                continue
        return posts

    def ids(self) -> set[str]:
        return {post.id for post in self.posts()}

    def append(self, posts: list[Post]) -> int:
        """Adds the posts the store does not hold yet, by id or by text; returns how many it added.
        A repost or a duplicate is dropped, a quote with a comment of its own stays."""
        existing = self.posts()
        known = {post.id for post in existing}
        signatures = []
        for post in existing:
            if not post.text:
                continue
            cached = self._sig_cache.get(post.id)
            if cached is None or cached[0] != post.network:
                cached = (post.network, _signature(post.text))
                self._sig_cache[post.id] = cached
            signatures.append(cached)
        fresh = []
        for post in posts:
            if post.id in known:
                continue
            signature = _signature(post.text)
            if signature and any(
                network == post.network and _similar(signature, other) for network, other in signatures
            ):
                continue
            fresh.append(post)
            if signature:
                signatures.append((post.network, signature))
        if not fresh:
            return 0
        self.root.mkdir(parents=True, exist_ok=True)
        with self.posts_file.open("a", encoding="utf-8") as log:
            for post in fresh:
                log.write(json.dumps(asdict(post), ensure_ascii=False) + "\n")
        return len(fresh)

    def save_media(self, post_id: str, index: int | str, data: bytes, extension: str) -> dict | None:
        """Writes one picture under the post's name; a format whose size cannot be measured is refused, since
        the card lays itself out by that size before the file is decoded."""
        size = image_size(data)
        if size is None:
            return None
        return self.save_file(post_id, index, data, extension, size=size)

    def save_file(self, post_id: str, index: int | str, data: bytes, extension: str, size: tuple[int, int] | None = None) -> dict | None:
        """Writes one attachment of a post — a picture with its measured size, a video without one."""
        if not data:
            return None
        self.media_dir.mkdir(parents=True, exist_ok=True)
        name = f"{safe(post_id)}-{index}.{extension}"
        (self.media_dir / name).write_bytes(data)
        entry = {"path": f"media/{name}"}
        if size is not None:
            entry["width"], entry["height"] = size
        return entry

    def builds(self) -> list[dict]:
        if not self.builds_file.exists():
            return []
        return [json.loads(line) for line in self.builds_file.read_text(encoding="utf-8").splitlines() if line]

    def built_ids(self) -> set[str]:
        return {post_id for build in self.builds() for post_id in build.get("post_ids", [])}

    def last_build_at(self) -> datetime | None:
        builds = self.builds()
        return datetime.fromisoformat(builds[-1]["at"]) if builds else None

    def unconsumed(self) -> list[Post]:
        built = self.built_ids()
        return [post for post in self.posts() if post.id not in built]

    def record_build(self, digest: dict) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        with self.builds_file.open("a", encoding="utf-8") as log:
            log.write(json.dumps(digest, ensure_ascii=False) + "\n")

    def source_statuses(self) -> list[dict]:
        if not self.sources_file.exists():
            return []
        return json.loads(self.sources_file.read_text(encoding="utf-8"))

    def save_source_statuses(self, statuses: list[dict]) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        self.sources_file.write_text(json.dumps(statuses, ensure_ascii=False, indent=2), encoding="utf-8")


def safe(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", name)


def _signature(text: str | None) -> frozenset[str]:
    """A post's text as character 5-grams; links, case and the `RT @handle:` prefix are noise."""
    if not text:
        return frozenset()
    flat = re.sub(r"\s+", " ", re.sub(r"https?://\S+", " ", text.lower())).strip()
    flat = re.sub(r"^rt @\w+:\s*", "", flat)
    if not flat:
        return frozenset()
    if len(flat) < 12:
        return frozenset([flat])
    return frozenset(flat[i:i + 5] for i in range(len(flat) - 4))


def _similar(first: frozenset[str], second: frozenset[str]) -> bool:
    """Near-identical texts share almost every gram; a quote with a comment of its own does not."""
    if not first or not second:
        return False
    return len(first & second) / len(first | second) >= 0.85


def image_size(data: bytes) -> tuple[int, int] | None:
    """Width and height from the file's own header, for the formats social networks serve."""
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) > 24:
        width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
        return (width, height) if width and height else None
    if data[:6] in (b"GIF87a", b"GIF89a") and len(data) > 10:
        width, height = int.from_bytes(data[6:8], "little"), int.from_bytes(data[8:10], "little")
        return (width, height) if width and height else None
    if data[:2] == b"\xff\xd8":
        index = 2
        while index + 9 < len(data):
            if data[index] != 0xFF:
                index += 1
                continue
            marker = data[index + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                height, width = int.from_bytes(data[index + 5:index + 7], "big"), int.from_bytes(data[index + 7:index + 9], "big")
                return (width, height) if width and height else None
            index += 2 + int.from_bytes(data[index + 2:index + 4], "big")
        return None
    return None

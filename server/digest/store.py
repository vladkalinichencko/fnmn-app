"""The post store on the Mac: one append-only log of every post the monitor collected, the media files it
downloaded, and the log of the digests already built. A post names its media by a path relative to `out/`,
so a build copies the files into the delivery without downloading anything again.

Posted times are ISO 8601 in UTC with a trailing `Z`, the same shape `DigestPackage` decodes on the phone.
"""

from __future__ import annotations

import fcntl
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
    attachments: list[dict] = field(default_factory=list)
    context: dict | None = None
    comments: list[dict] = field(default_factory=list)
    stats: dict | None = None
    folders: list[str] = field(default_factory=list)
    thread: str | None = None
    media_errors: int = 0

    def __post_init__(self) -> None:
        """Instagram's `og:title` is `Name on Instagram: "caption"`; the card wants only the name, and
        `@handle` stands in for a missing display name. Rows written before the fix carry the raw title.
        The shortcode names a post by itself, so an id that still carries an author — guessed wrong in
        the feed — collapses to it."""
        if self.network == "instagram":
            raw = self.author.get("name") or ""
            match = re.match(r"^(.*?) on Instagram\b", raw)
            name = (match.group(1) if match else raw).strip()
            if not name or name.startswith("@"):
                name = self.author.get("handle") or name
            self.author = {**self.author, "name": name}
            match = re.fullmatch(r"instagram/[^/]+/([A-Za-z0-9_-]+)", self.id)
            if match:
                self.id = f"instagram/{match.group(1)}"


def _legacy_row(row: dict) -> dict:
    """A row written while a post kept `media` and `video` apart reads as the same post's attachments:
    the pictures first, the video after them, each tagged with its kind."""
    if "media" not in row and "video" not in row:
        return row
    row = dict(row)
    media = row.pop("media", None) or []
    video = row.pop("video", None)
    attachments = [{"kind": "image", **item} for item in media]
    if video:
        attachments.append({"kind": "video", "file": video.get("file"), "poster": video.get("poster")})
    row["attachments"] = attachments
    return row


def wire(post: Post) -> dict:
    """A post as the phone's `DigestPackage.Post` decodes it: camelCase keys, one level of context."""
    return {
        "id": post.id,
        "network": post.network,
        "author": post.author,
        "permalink": post.permalink,
        "postedAt": post.posted_at,
        "text": post.text,
        "attachments": post.attachments,
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
            "attachments": _context_attachments(post),
            "stats": post.get("stats"),
        },
    }


def _context_attachments(post: dict) -> list[dict]:
    """A context post's attachments in the current shape; rows collected before attachments
    existed carry `media` and `video`, which read as the same list."""
    if "attachments" in post:
        return post["attachments"]
    attachments = [{"kind": "image", **item} for item in post.get("media") or []]
    video = post.get("video")
    if video:
        attachments.append({"kind": "video", "file": video.get("file"), "poster": video.get("poster")})
    return attachments


class Store:
    def __init__(self, root: Path = OUT):
        self.root = root
        self.posts_file = root / "posts.jsonl"
        self.builds_file = root / "builds.jsonl"
        self.sources_file = root / "sources.json"
        self.media_dir = root / "media"
        self._sig_cache: dict[tuple[str, str | None], tuple[str, frozenset[str]]] = {}
        self._posts_cache: tuple[tuple[int, int], list[Post]] | None = None

    def posts(self) -> list[Post]:
        """Every collected post, oldest first. A run that died mid-line leaves a torn tail, which is skipped;
        the next run appends after it. The file is re-read only when it changed on disk."""
        try:
            stat = self.posts_file.stat()
        except FileNotFoundError:
            return []
        signature = (stat.st_mtime_ns, stat.st_size)
        if self._posts_cache is not None and self._posts_cache[0] == signature:
            return self._posts_cache[1]
        posts = []
        for line in self.posts_file.read_text(encoding="utf-8").split("\n"):
            try:
                posts.append(Post(**_legacy_row(json.loads(line))))
            except (json.JSONDecodeError, TypeError):
                continue
        self._posts_cache = (signature, posts)
        return posts

    def ids(self) -> set[str]:
        return {post.id for post in self.posts()}

    def append(self, posts: list[Post]) -> int:
        """Adds the posts the store does not hold yet, by id or by text; returns how many it added.
        A repost or a duplicate is dropped, a quote with a comment of its own stays. The lock keeps a
        manual monitor run and the launchd one from interleaving their appends."""
        self.root.mkdir(parents=True, exist_ok=True)
        with self.posts_file.with_suffix(".lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            return self._append_locked(posts)

    def _append_locked(self, posts: list[Post]) -> int:
        existing = self.posts()
        known = {post.id for post in existing}
        signatures = []
        texts: list[tuple[str, str, str]] = []
        wanted = {(post.network, post.source) for post in posts}
        for post in existing:
            if not post.text:
                continue
            key = (post.id, post.text)
            cached = self._sig_cache.get(key)
            if cached is None or cached[0] != post.network:
                cached = (post.network, _signature(post.text))
                self._sig_cache[key] = cached
            signatures.append(cached)
            if (post.network, post.source) in wanted:
                texts.append((post.network, post.source, flat_text(post.text)))
        fresh = []
        for post in posts:
            if post.id in known:
                continue
            known.add(post.id)
            signature = _signature(post.text)
            if signature and any(
                network == post.network and _similar(signature, other) for network, other in signatures
            ):
                continue
            flat = flat_text(post.text)
            if flat and not post.attachments and any(
                network == post.network and source == post.source and prefix_of(flat, other)
                for network, source, other in texts
            ):
                continue
            fresh.append(post)
            if signature:
                signatures.append((post.network, signature))
            if flat:
                texts.append((post.network, post.source, flat))
        if not fresh:
            return 0
        with self.posts_file.open("a", encoding="utf-8") as log:
            for post in fresh:
                log.write(json.dumps(asdict(post), ensure_ascii=False) + "\n")
        self._posts_cache = None
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
        return [json.loads(line) for line in self.builds_file.read_text(encoding="utf-8").split("\n") if line]

    def built_ids(self, deliveries: Path | None = None) -> set[str]:
        """The post ids a build record consumed. A `pending` record — written before its tar — counts
        only when the tar it names is actually in `deliveries`, so a crash between the two never ships
        a post twice nor loses it."""
        built = set()
        for build in self.builds():
            post_ids = set(build.get("post_ids", []))
            if build.get("pending"):
                if deliveries is not None and build.get("file") and (deliveries / build["file"]).exists():
                    built |= post_ids
            else:
                built |= post_ids
        return built

    def last_build_at(self) -> datetime | None:
        builds = [build for build in self.builds() if not build.get("pending")]
        return datetime.fromisoformat(builds[-1]["at"]) if builds else None

    def unconsumed(self, deliveries: Path | None = None) -> list[Post]:
        built = self.built_ids(deliveries)
        return [post for post in self.posts() if post.id not in built]

    def record_build(self, digest: dict) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        with self.builds_file.with_suffix(".lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
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


def flat_text(text: str | None) -> str:
    """A post's text with every whitespace run folded and case dropped — the form two spellings of
    the same words share."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip().casefold()


_PREFIX_MIN = 120
_ELLIPSIS = re.compile(r"(?:…|\.\.\.)\s*$")


def prefix_of(shorter: str, longer: str) -> bool:
    """`shorter` opens `longer` verbatim — a channel that reposts its text as a media caption gets
    the caption cut at an ellipsis, and the cut copy is the same post. Only a long matching prefix
    counts; two posts that merely start alike stay."""
    for cut in (shorter, _ELLIPSIS.sub("", shorter)):
        if len(cut) >= _PREFIX_MIN and len(longer) > len(cut) and longer.startswith(cut):
            return True
    return False


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

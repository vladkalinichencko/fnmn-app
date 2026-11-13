"""The source contract: every network is one module with the same call.

    collect(source, web, store, folders, report, page=None) -> SourceResult

X, Instagram and Telegram read through `page`, a tab of the reader browser on the network's
logged-in profile; the monitor opens it with `browser(network)`. Telegram also reads a channel
whose public page is enough through `web`, where no `page` is passed. `report` names the stage
for the monitor log; a source that read only part of its list says so in `SourceResult.note`
instead of pretending the run was complete.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterator

import httpx

from datetime import datetime, timedelta

from digest.store import Post
from web import Web
import reader

BROWSER = {"x", "instagram", "telegram"}
"""The networks read through a logged-in profile; Telegram also has a public page."""

THREAD_GAP = timedelta(minutes=30)
"""Posts of one author this close together read as one story; the build scores and caps them as one."""


def mark_threads(posts: list[Post], store) -> None:
    """Writes each post's `thread`: the id of the first post of its run. A run is one author's
    consecutive posts inside `THREAD_GAP`; a run that reaches back into the store keeps the
    thread it already had, so a story split across monitor passes still reads as one."""
    latest: dict[tuple[str, str], Post] = {}
    for old in store.posts():
        key = (old.source, old.author.get("handle") or "")
        if key not in latest or old.posted_at > latest[key].posted_at:
            latest[key] = old
    last = dict(latest)
    for post in sorted(posts, key=lambda item: item.posted_at):
        key = (post.source, post.author.get("handle") or "")
        previous = last.get(key)
        gap = None
        if previous is not None:
            gap = datetime.fromisoformat(post.posted_at) - datetime.fromisoformat(previous.posted_at)
        if previous is not None and timedelta(0) <= gap <= THREAD_GAP:
            post.thread = previous.thread or previous.id
        else:
            post.thread = None
        last[key] = post


@dataclass
class SourceResult:
    posts: list[Post] = field(default_factory=list)
    name: str | None = None
    note: str | None = None


class SourceFailure(Exception):
    """The network refused the reader; the reason reaches the digest's source status."""

    def __init__(self, reason: str):
        self.reason = reason
        super().__init__(reason)


def profile(network: str) -> Path:
    return reader.profile(network)


def needs_browser(network: str) -> bool:
    return network in BROWSER


@contextmanager
def browser(network: str) -> Iterator[reader.Tab]:
    """The logged-in profile of one network, in the reader browser."""
    with reader.job(network) as tab:
        yield tab


def page_fetch(tab) -> Callable[[str], bytes]:
    """Downloads through the logged-in tab's own cookies, so a CDN sees the profile's session."""
    fetch = getattr(tab, "fetch", None)
    if fetch is not None:
        return fetch

    def fetch_url(url: str) -> bytes:
        try:
            response = tab.context.request.get(url, timeout=30_000)
        except Exception as error:
            raise OSError(str(error)) from error
        if response.status >= 400:
            raise OSError(f"the picture returned HTTP {response.status}")
        return response.body()

    return fetch_url


def save_photo(web: Web, store, post_id: str, index: int | str, url: str, fetch: Callable[[str], bytes] | None = None) -> dict | None:
    """One picture of a post, written under its own name. A picture the network will not serve is left out of
    the post instead of stopping it: the card then shows the text without that picture."""
    try:
        data = fetch(url) if fetch is not None else web.bytes(url)
    except (OSError, httpx.HTTPError):
        return None
    extension = "png" if url.split("?")[0].lower().endswith(".png") else "jpg"
    return store.save_media(post_id, index, data, extension)


MAX_VIDEO_BYTES = 400 * 1024 * 1024
"""A post's video travels inside the digest tar, so it stays under the size iCloud comfortably carries."""


def save_video(web: Web, store, post_id: str, index: int | str, url: str, fetch: Callable[[str], bytes] | None = None) -> dict | None:
    """One video file of a post. A refused or oversized file is left out like a refused picture."""
    try:
        data = fetch(url) if fetch is not None else web.bytes(url)
    except (OSError, httpx.HTTPError):
        return None
    if not data or len(data) > MAX_VIDEO_BYTES:
        return None
    extension = url.split("?")[0].rsplit(".", 1)[-1].lower()
    if extension not in {"mp4", "mov", "m4v", "webm"}:
        extension = "mp4"
    return store.save_file(post_id, index, data, extension)

"""Refetch one post's pictures when the phone asks, instead of rebuilding the whole digest.

The Mac owns the logged-in profiles and the store, so the phone sends a post id and gets back the media
entries it can download from the same server. A source that still refuses the picture is retried a few
times; the phone shows the placeholder and can ask again.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

from digest.monitor import SOURCES
from digest.reading import browser, needs_browser
from digest.store import Post, Store
from web import LIVE

HERE = Path(__file__).resolve().parent
ATTEMPTS = 3


def refresh(post_id: str, store: Store | None = None, collect=None, subscriptions: dict | None = None) -> list[dict]:
    """The media of one post, fetched again from its source; raises when the source still has none."""
    store = store or Store()
    post = next((item for item in store.posts() if item.id == post_id), None)
    if post is None:
        raise LookupError(post_id)
    source = _source(post.source, subscriptions)
    module = SOURCES[post.network]
    if collect is None:
        collect = _collect
    last: Exception | None = None
    for attempt in range(ATTEMPTS):
        try:
            posts = collect(module, source, post.folders)
        except Exception as error:
            last = error
        else:
            found = next((item for item in posts if item.id == post_id), None)
            if found is not None:
                media = _media(found)
                if media:
                    return media
        if attempt + 1 < ATTEMPTS:
            time.sleep(2 * (attempt + 1))
    if last is not None:
        raise ValueError(f"the source did not answer: {last}") from last
    raise ValueError("the source did not return a picture this time")


def _media(post: Post) -> list[dict]:
    media = list(post.media)
    poster = (post.video or {}).get("poster")
    if poster:
        media.append(poster)
    return media


def _source(source_id: str, subscriptions: dict | None = None) -> dict:
    if subscriptions is None:
        subscriptions = json.loads((HERE / "subscriptions.json").read_text(encoding="utf-8"))
    for source in subscriptions["sources"]:
        if source["id"] == source_id:
            return source
    raise LookupError(source_id)


def _collect(module, source: dict, folders: list[str]) -> list[Post]:
    report = lambda stage: None
    if needs_browser(source["network"]):
        with browser(source["network"]) as page:
            return module.collect(source, LIVE, Store(), folders, report, page=page).posts
    return module.collect(source, LIVE, Store(), folders, report).posts

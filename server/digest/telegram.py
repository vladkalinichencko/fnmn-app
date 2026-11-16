"""Telegram public channels: the web preview at t.me/s/<channel> lists the recent messages as plain HTML and
needs no login. A channel busy enough to overflow one page is read back through its `before=` link. The
account's own read state comes from the `tg` CLI once per monitor run: a channel's unread messages are
always the newest tail of it, so only that tail joins the digest — a post already read in Telegram never
does, and a channel the account never opens still gives its recent backlog."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path

from lxml import html

from package import Report
from digest.reading import SourceFailure, SourceResult, page_fetch, save_photo, save_video
from digest.store import Post, iso
from web import Web

PAGE = "https://t.me/s/{channel}"
MORE = re.compile(r"before=(\d+)")
MAX_PAGES = 3

_UNREAD_COUNTS: tuple[float, dict[str, int] | None] | None = None
_UNREAD_TTL = 3600.0


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    if source.get("scope") == "recommendations":
        raise SourceFailure("Telegram has no recommendation feed the reader can open")
    channel = source["channel"]
    counts = _unread_counts()
    unread = counts.get(channel.lstrip("@").lower()) if counts is not None else None
    if unread == 0:
        return SourceResult(posts=[], note="nothing unread in the channel")
    known = store.ids()
    collected: dict[str, Post] = {}
    name = None
    before = None
    skipped = 0
    fetch = page_fetch(page) if page is not None else None
    for _ in range(MAX_PAGES):
        report(f"reading t.me/{channel}")
        url = PAGE.format(channel=channel) + (f"?before={before}" if before else "")
        if page is not None:
            try:
                page.goto(url)
            except Exception as error:
                raise SourceFailure(f"t.me/{channel} did not load: {error}") from error
            document = html.fromstring(page.html())
        else:
            document = html.fromstring(web.text(url))
        messages = document.xpath('//div[contains(@class,"tgme_widget_message_wrap")]')
        if not messages:
            raise SourceFailure(f"t.me/{channel} showed no messages; is the channel public?")
        page_ids = []
        for message in messages:
            post = _post(message, channel, source, web, store, folders, fetch)
            if post is None:
                skipped += 1
                continue
            page_ids.append(post.id)
            collected.setdefault(post.id, post)
            if name is None:
                name = post.author["name"]
        before = _older(document)
        if before is None or any(post_id in known for post_id in page_ids):
            break
    posts = sorted(collected.values(), key=lambda post: post.posted_at)
    read = len(posts)
    if unread is not None:
        tail = _unread_tail(posts, unread)
        posts = tail
        read -= len(tail)
    fresh = [post for post in posts if post.id not in known]
    skipped_store = len(posts) - len(fresh)
    posts = fresh
    notes = []
    if read:
        notes.append(f"{read} posts were already read in Telegram")
    if skipped_store:
        notes.append(f"{skipped_store} posts were already in the digest")
    if skipped:
        notes.append(f"{skipped} messages had no text, media or time")
    return SourceResult(posts=posts, name=name, note="; ".join(notes) or None)


def _unread_tail(posts: list[Post], unread: int) -> list[Post]:
    """The newest `unread` posts by message id. Telegram's read state is one watermark per channel, so
    everything past it is unread and it always sits at the tail; a few ids lost to edits or deletions
    can shift the boundary by a post, which the digest tolerates."""
    if unread <= 0:
        return []
    if unread >= len(posts):
        return posts
    ids = sorted((int(post.id.rsplit("/", 1)[-1]) for post in posts), reverse=True)
    boundary = ids[unread - 1]
    return [post for post in posts if int(post.id.rsplit("/", 1)[-1]) >= boundary]


def _telegram_cli() -> str | None:
    candidates = [shutil.which("telegram"), str(Path.home() / ".local" / "bin" / "telegram")]
    for candidate in candidates:
        if candidate and os.access(candidate, os.X_OK):
            return candidate
    return None


def _unread_counts() -> dict[str, int] | None:
    """Unread message counts per channel username, one `tg chats` pair an hour — the main list
    and the archive folder are separate listings. None when the CLI cannot answer; a source then reads
    by recency as it did before the read state existed."""
    global _UNREAD_COUNTS
    now = time.monotonic()
    if _UNREAD_COUNTS is not None and now - _UNREAD_COUNTS[0] < _UNREAD_TTL:
        return _UNREAD_COUNTS[1]
    cli = _telegram_cli()
    counts: dict[str, int] | None = None
    if cli is not None:
        gathered: dict[str, int] = {}
        for archived in (False, True):
            for chat in _chats(cli, archived):
                username = (chat.get("username") or "").lstrip("@").lower()
                if username:
                    gathered[username] = chat.get("unreadCount") or 0
        counts = gathered or None
    _UNREAD_COUNTS = (now, counts)
    return counts


def _chats(cli: str, archived: bool) -> list[dict]:
    args = [cli, "chats", "--json", "-n", "1000"]
    if archived:
        args.append("--archived")
    try:
        done = subprocess.run(args, capture_output=True, timeout=120, text=True)
        chats = json.loads(done.stdout)
    except Exception:
        return []
    return chats if isinstance(chats, list) else []


def _older(document) -> str | None:
    more = document.xpath('//a[contains(@class,"tme_messages_more")]/@href')
    match = MORE.search(more[0]) if more else None
    return match.group(1) if match else None


def _post(message, channel: str, source: dict, web: Web, store, folders: list[str], fetch=None) -> Post | None:
    data_post = message.xpath(".//*[@data-post]/@data-post")
    if not data_post:
        return None
    message_id = data_post[0].split("/")[-1]
    post_id = f"telegram/{channel}/{message_id}"
    times = message.xpath('.//time/@datetime')
    if not times:
        return None
    posted = iso(datetime.fromisoformat(times[0]))
    text = _markdown(message.xpath('.//div[contains(@class,"tgme_widget_message_text")]'))
    media = []
    errors = 0
    for index, style in enumerate(message.xpath('.//a[contains(@class,"tgme_widget_message_photo_wrap")]/@style')):
        url = _background(style)
        if url:
            saved = save_photo(web, store, post_id, index, url, fetch)
            if saved:
                media.append(saved)
            else:
                errors += 1
    video, video_errors = _video(message, post_id, web, store, fetch)
    errors += video_errors
    if not text and not media and not video:
        return None
    owner = message.xpath('.//*[contains(@class,"tgme_widget_message_owner_name")]//text()')
    author = {"handle": channel, "name": owner[0].strip() if owner else channel}
    return Post(
        id=post_id,
        network="telegram",
        source=source["id"],
        author=author,
        permalink=f"https://t.me/{channel}/{message_id}",
        posted_at=posted,
        text=text,
        media=media,
        video=video,
        folders=folders,
        media_errors=errors,
    )


def _video(message, post_id: str, web: Web, store, fetch=None) -> tuple[dict | None, int]:
    thumbs = message.xpath('.//*[contains(@class,"tgme_widget_message_video_thumb")]/@style')
    if not thumbs:
        return None, 0
    url = _background(thumbs[0])
    poster = save_photo(web, store, post_id, "poster", url, fetch) if url else None
    errors = 1 if url and poster is None else 0
    sources = message.xpath('.//video[contains(@class,"tgme_widget_message_video")]/@src')
    video_file = save_video(web, store, post_id, "video", sources[0], fetch) if sources else None
    return {"poster": poster, "file": video_file}, errors


def _background(style: str) -> str | None:
    match = re.search(r"url\(['\"]?(.*?)['\"]?\)", style)
    return match.group(1) if match else None


def _markdown(elements) -> str | None:
    """The message text as Markdown keeps it: line breaks stand, and a link keeps its address next to its
    label, which the reader turns into a link."""
    if not elements:
        return None
    fragment = elements[0]
    for line in fragment.xpath(".//br"):
        line.tail = "\n" + (line.tail or "")
    for link in fragment.xpath(".//a"):
        href = link.get("href") or ""
        label = (link.text_content() or "").strip()
        if href.startswith("http") and href not in label:
            link.tail = f" ({href})" + (link.tail or "")
    text = fragment.text_content()
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text or None



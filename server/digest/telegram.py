"""Telegram public channels: the web preview at t.me/s/<channel> lists the recent messages as plain HTML and
needs no login. A channel busy enough to overflow one page is read back through its `before=` link."""

from __future__ import annotations

import re
from datetime import datetime

from lxml import html

from package import Report
from digest.reading import SourceFailure, SourceResult, page_fetch, save_photo
from digest.store import Post, iso
from web import Web

PAGE = "https://t.me/s/{channel}"
MORE = re.compile(r"before=(\d+)")
MAX_PAGES = 3


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    channel = source["channel"]
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
                page.goto(url, wait_until="domcontentloaded", timeout=45_000)
            except Exception as error:
                raise SourceFailure(f"t.me/{channel} did not load: {error}") from error
            document = html.fromstring(page.content())
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
    note = f"{skipped} messages had no text, media or time" if skipped else None
    return SourceResult(posts=sorted(collected.values(), key=lambda post: post.posted_at), name=name, note=note)


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
    for index, style in enumerate(message.xpath('.//a[contains(@class,"tgme_widget_message_photo_wrap")]/@style')[:4]):
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
    lengths = message.xpath('.//*[contains(@class,"tgme_widget_message_video_duration")]/text()')
    return {"poster": poster, "duration": _seconds(lengths[0]) if lengths else None}, errors


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


def _seconds(value: str) -> float | None:
    parts = value.strip().lstrip(">").split(":")
    try:
        numbers = [int(part) for part in parts]
    except ValueError:
        return None
    seconds = 0.0
    for number in numbers:
        seconds = seconds * 60 + number
    return seconds

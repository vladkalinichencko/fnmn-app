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
import tempfile
import time
from datetime import datetime
from pathlib import Path

from lxml import html

from package import Report
from digest.reading import MAX_VIDEO_BYTES, SourceFailure, SourceResult, page_fetch, save_photo, save_video
from digest.store import Post, iso
from web import Web

PAGE = "https://t.me/s/{channel}"
MORE = re.compile(r"before=(\d+)")
MAX_PAGES = 3

_UNREAD_COUNTS: tuple[float, tuple[dict[str, int], set[str]] | None] | None = None
_UNREAD_TTL = 3600.0


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    if source.get("scope") == "recommendations":
        raise SourceFailure("Telegram has no recommendation feed the reader can open")
    channel = source["channel"]
    read_state = _unread_counts()
    unread = None
    if read_state is not None:
        counts, archived = read_state
        key = channel.lstrip("@").lower()
        if key in archived:
            return SourceResult(posts=[], note="archived in Telegram")
        unread = counts.get(key)
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


def _unread_counts() -> tuple[dict[str, int], set[str]] | None:
    """Unread message counts per channel username and the usernames sitting in the archive folder, one
    `tg chats` pair an hour — the main list and the archive folder are separate listings. None when the
    CLI cannot answer; a source then reads by recency as it did before the read state existed."""
    global _UNREAD_COUNTS
    now = time.monotonic()
    if _UNREAD_COUNTS is not None and now - _UNREAD_COUNTS[0] < _UNREAD_TTL:
        return _UNREAD_COUNTS[1]
    cli = _telegram_cli()
    state: tuple[dict[str, int], set[str]] | None = None
    if cli is not None:
        counts: dict[str, int] = {}
        archived: set[str] = set()
        for is_archived in (False, True):
            for chat in _chats(cli, is_archived):
                username = (chat.get("username") or "").lstrip("@").lower()
                if not username:
                    continue
                if is_archived:
                    archived.add(username)
                counts[username] = chat.get("unreadCount") or 0
        state = (counts, archived) if counts or archived else None
    _UNREAD_COUNTS = (now, state)
    return state


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
    permalink = f"https://t.me/{channel}/{message_id}"
    text = _markdown(message.xpath('.//div[contains(@class,"tgme_widget_message_text")]'))
    attachments = []
    errors = 0
    items = message.xpath(
        './/*[contains(@class,"tgme_widget_message_photo_wrap")'
        ' or contains(@class,"tgme_widget_message_video_player")'
        ' or contains(@class,"tgme_widget_message_roundvideo_player")]'
    )
    for index, item in enumerate(items):
        if "tgme_widget_message_photo_wrap" in (item.get("class") or ""):
            url = _background(item.get("style") or "")
            saved = save_photo(web, store, post_id, index, url, fetch) if url else None
            if saved:
                attachments.append({"kind": "image", **saved})
            else:
                errors += 1
        else:
            attachment, failed = _video(item, post_id, index, web, store, fetch, permalink)
            if attachment is not None:
                attachments.append(attachment)
            errors += failed
    if not text and not attachments:
        return None
    owner = message.xpath('.//*[contains(@class,"tgme_widget_message_owner_name")]//text()')
    author = {"handle": channel, "name": owner[0].strip() if owner else channel}
    return Post(
        id=post_id,
        network="telegram",
        source=source["id"],
        author=author,
        permalink=permalink,
        posted_at=posted,
        text=text,
        attachments=attachments,
        folders=folders,
        media_errors=errors,
    )


def _video(player, post_id: str, index: int, web: Web, store, fetch=None, link: str = "") -> tuple[dict | None, int]:
    """One video attachment: the poster always comes from the thumbnail, the file from the player's own
    `<video>` when Telegram serves it anonymously — a `not_supported` player ("Media is too big") has none,
    and the file then comes through the account's own client, which reads what the public page refuses.
    Round videos (`..._roundvideo_player`) carry the same thumb and `<video>` under their own classes."""
    thumbs = player.xpath('.//*[contains(@class,"video_thumb")]/@style')
    url = _background(thumbs[0]) if thumbs else None
    poster = save_photo(web, store, post_id, f"{index}-poster", url, fetch) if url else None
    errors = 1 if url and poster is None else 0
    sources = player.xpath('.//video/@src')
    video_file = save_video(web, store, post_id, f"{index}-video", sources[0], fetch) if sources else None
    if video_file is None:
        video_file = _cli_video(player, post_id, index, store, link)
    if video_file is None and poster is None:
        return None, errors + 1
    return {"kind": "video", "file": video_file, "poster": poster}, errors


def _cli_video(player, post_id: str, index: int, store, link: str = "") -> dict | None:
    """The mp4 a `not_supported` player hides, fetched by message id through `tg download`: the player's
    own link names the message the media belongs to, which in a grouped album is not the bubble's; a
    round-video player is a plain div, so the bubble's permalink stands in for it."""
    cli = _telegram_cli()
    href = player.get("href") or link
    match = re.search(r"t\.me/([^/?#]+)/(\d+)", href)
    if cli is None or not match:
        return None
    channel, message_id = match.group(1), match.group(2)
    with tempfile.TemporaryDirectory(prefix="reed-tg-") as scratch:
        try:
            done = subprocess.run(
                [cli, "download", f"@{channel}", message_id, "-o", scratch, "--json"],
                capture_output=True, timeout=600, text=True,
            )
        except Exception:
            return None
        for path in _downloaded(done.stdout):
            try:
                size = Path(path).stat().st_size
                if not size or size > MAX_VIDEO_BYTES:
                    continue
                data = Path(path).read_bytes()
            except OSError:
                continue
            extension = path.rsplit(".", 1)[-1].lower()
            if extension not in {"mp4", "mov", "m4v", "webm"}:
                extension = "mp4"
            return store.save_file(post_id, f"{index}-video", data, extension)
    return None


def _downloaded(output: str) -> list[str]:
    """The file paths a `tg download --json` answer names; the CLI prints one object or a list of them."""
    try:
        payload = json.loads(output[output.index("{"):]) if "{" in output else json.loads(output)
    except (ValueError, json.JSONDecodeError):
        return []
    items = payload if isinstance(payload, list) else [payload]
    paths = []
    for item in items:
        if isinstance(item, dict):
            for key in ("filePath", "path", "file"):
                if isinstance(item.get(key), str):
                    paths.append(item[key])
                    break
            media = item.get("media") or {}
            if isinstance(media, dict) and isinstance(media.get("path"), str):
                paths.append(media["path"])
    return paths


def _background(style: str) -> str | None:
    match = re.search(r"url\(['\"]?(.*?)['\"]?\)", style)
    return match.group(1) if match else None


def _markdown(elements) -> str | None:
    """The message text as Markdown: the widget's semantic tags become the marks the reader already
    draws — `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`, `[label](href)` — and a `<br>` stays a
    line break. A spoiler's bars are Telegram's own markup and would print literally, so its words stay."""
    if not elements:
        return None
    text = _content(elements[0])
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text or None


def _content(node) -> str:
    parts = [node.text or ""]
    for child in node:
        parts.append(_piece(child))
        parts.append(child.tail or "")
    return "".join(parts)


def _piece(node) -> str:
    tag = node.tag if isinstance(node.tag, str) else ""
    if tag == "br":
        return "\n"
    if tag in {"b", "strong"}:
        return _marked(_content(node), "**")
    if tag in {"i", "em"}:
        return _marked(_content(node), "*")
    if tag in {"s", "strike", "del"}:
        return _marked(_content(node), "~~")
    if tag == "code":
        return _inline_code(_content(node))
    if tag == "a":
        return _link(node)
    if tag == "tg-spoiler":
        return _content(node)
    return _content(node)


def _marked(text: str, mark: str) -> str:
    inner = text.strip()
    if not inner:
        return text
    lead = text[: len(text) - len(text.lstrip())]
    trail = text[len(text.rstrip()) :]
    return f"{lead}{mark}{inner}{mark}{trail}"


def _inline_code(text: str) -> str:
    inner = text.strip()
    if not inner:
        return text
    fence = "`" * (max((len(run) for run in re.findall(r"`+", inner)), default=0) + 1)
    pad = " " if inner.startswith("`") or inner.endswith("`") else ""
    lead = text[: len(text) - len(text.lstrip())]
    trail = text[len(text.rstrip()) :]
    return f"{lead}{fence}{pad}{inner}{pad}{fence}{trail}"


def _link(node) -> str:
    href = node.get("href") or ""
    label = _content(node).strip()
    if label and href.startswith("http"):
        return f"[{label}]({href})"
    return label or href



"""X posts. The timeline page of the logged-in profile gives the ids of recent posts; the public syndication
endpoint then returns each post's full JSON, media sizes and quoted or answered post included, without a second
page load. Replies of the few most discussed posts are read from the permalink page while it is still open.
"""

from __future__ import annotations

import json
import re
import time
from datetime import datetime

import httpx

from package import Report
from digest.reading import SourceFailure, SourceResult, page_fetch, save_photo, save_video
from digest.store import Post, iso
from web import Web

HOME = "https://x.com"
SYNDICATION = "https://cdn.syndication.twimg.com/tweet-result"
STATUS = re.compile(r"/status/(\d+)")
REQUEST_PAUSE = 0.4
TOP_DISCUSSED = 3
FEED = f"{HOME}/home"
FEED_LIMIT = 40


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    if page is None:
        raise SourceFailure("X needs the logged-in profile")
    if source.get("scope") == "recommendations":
        report("reading the For you feed")
        ids = _feed(page)
        handle = ""
    else:
        handle = source["handle"]
        report(f"reading x.com/{handle}")
        ids = _timeline(page, handle)
    posts: list[Post] = []
    note = None
    fetch = page_fetch(page)
    for status_id in ids:
        try:
            payload = _tweet(web, status_id)
        except httpx.HTTPStatusError as error:
            if error.response.status_code == 429:
                note = "X rate-limited the reader"
                break
            continue
        except OSError:
            note = "x.com stopped answering"
            break
        if payload is None:
            continue
        post = _post(payload, handle, source, web, store, folders, fetch, page=page)
        if post is not None:
            posts.append(post)
        time.sleep(REQUEST_PAUSE)
    for post in sorted(posts, key=lambda post: (post.stats or {}).get("replies") or 0, reverse=True)[:TOP_DISCUSSED]:
        if (post.stats or {}).get("replies"):
            try:
                post.comments = _replies(page, post)
            except (OSError, SourceFailure):
                note = note or "the replies did not load"
    name = next((post.author["name"] for post in posts if post.author["name"]), None)
    return SourceResult(posts=sorted(posts, key=lambda post: post.posted_at), name=name, note=note)


def _timeline(tab, handle: str) -> list[str]:
    """The status ids on the profile timeline, in the order the page shows them, newest first."""
    try:
        tab.goto(f"{HOME}/{handle}")
        if "/login" in tab.url:
            raise SourceFailure("the login expired; run python -m digest.login x")
        tab.wait_for_selector('[data-testid="tweet"]', timeout=20)
    except SourceFailure:
        raise
    except Exception as error:
        raise SourceFailure(f"x.com/{handle} did not show its timeline: {error}") from error
    pattern = re.compile(rf"/{re.escape(handle)}/status/(\d+)", re.IGNORECASE)
    seen: list[str] = []
    for _ in range(4):
        hrefs = tab.eval_on_selector_all('a[href*="/status/"]', "e => e.getAttribute('href')") or []
        for href in hrefs:
            match = pattern.match(href or "")
            if match and match.group(1) not in seen:
                seen.append(match.group(1))
        tab.wheel(1400)
        tab.wait_for_timeout(900)
    return seen


def _feed(tab) -> list[str]:
    """The For you timeline's status ids, whatever author posted them; capped, since every id costs a request."""
    try:
        tab.goto(FEED)
        if "/login" in tab.url:
            raise SourceFailure("the login expired; run python -m digest.login x")
        tab.wait_for_selector('[data-testid="tweet"]', timeout=20)
    except SourceFailure:
        raise
    except Exception as error:
        raise SourceFailure(f"the For you feed did not load: {error}") from error
    seen: list[str] = []
    for _ in range(4):
        hrefs = tab.eval_on_selector_all('a[href*="/status/"]', "e => e.getAttribute('href')") or []
        for href in hrefs:
            match = STATUS.search(href or "")
            if match and match.group(1) not in seen:
                seen.append(match.group(1))
        if len(seen) >= FEED_LIMIT:
            break
        tab.wheel(1400)
        tab.wait_for_timeout(900)
    return seen[:FEED_LIMIT]


def _tweet(web: Web, status_id: str) -> dict | None:
    payload = json.loads(web.text(f"{SYNDICATION}?id={status_id}&token=a&lang=en"))
    return payload if payload.get("__typename") == "Tweet" else None


def _post(payload: dict, handle: str, source: dict, web: Web, store, folders: list[str], fetch=None, page=None) -> Post | None:
    status_id = payload.get("id_str")
    if not status_id:
        return None
    user = payload.get("user") or {}
    author = {
        "handle": user.get("screen_name") or handle,
        "name": user.get("name") or handle,
    }
    post_id = f"x/{status_id}"
    permalink = f"{HOME}/{author['handle']}/status/{status_id}"
    text = (payload.get("text") or "").strip() or None
    if payload.get("note_tweet") and page is not None:
        text = _note_text(page, permalink) or text
    media, video, errors = _media(payload, post_id, web, store, fetch)
    stats = {
        "likes": payload.get("favorite_count"),
        "reposts": payload.get("retweet_count"),
        "replies": payload.get("conversation_count"),
    }
    return Post(
        id=post_id,
        network="x",
        source=source["id"],
        author=author,
        permalink=permalink,
        posted_at=iso(datetime.fromisoformat(payload["created_at"])),
        text=text,
        media=media,
        video=video,
        context=_context(payload),
        stats=stats,
        folders=folders,
        media_errors=errors,
    )


NOTE_TEXT = """document.querySelector('[data-testid="tweetText"]')?.innerText"""


def _note_text(tab, permalink: str) -> str | None:
    """A long post's whole body: the syndication payload carries only a preview of it."""
    try:
        tab.goto(permalink)
        tab.wait_for_selector('[data-testid="tweetText"]', timeout=20)
        text = tab.eval(NOTE_TEXT)
    except Exception:
        return None
    return text.strip() if isinstance(text, str) and text.strip() else None


def _media(payload: dict, post_id: str, web: Web, store, fetch=None) -> tuple[list[dict], dict | None, int]:
    media: list[dict] = []
    video = None
    errors = 0
    for index, item in enumerate(payload.get("mediaDetails") or []):
        kind = item.get("type")
        url = item.get("media_url_https")
        if not url:
            continue
        if kind == "photo":
            saved = save_photo(web, store, post_id, index, f"{url}?name=large", fetch)
            if saved:
                media.append(saved)
            else:
                errors += 1
        elif kind in ("video", "animated_gif") and video is None:
            poster = save_photo(web, store, post_id, "poster", url, fetch)
            if poster is None:
                errors += 1
            video = {"poster": poster, "file": _video_file(item, post_id, web, store, fetch)}
    return media, video, errors


def _video_file(item: dict, post_id: str, web: Web, store, fetch=None) -> dict | None:
    """The best mp4 variant of the tweet's video, as a file the digest carries."""
    variants = [
        variant for variant in (item.get("video_info") or {}).get("variants") or []
        if variant.get("content_type") == "video/mp4" and variant.get("url")
    ]
    if not variants:
        return None
    best = max(variants, key=lambda variant: variant.get("bitrate") or 0)
    return save_video(web, store, post_id, "video", best["url"], fetch)


def _context(payload: dict) -> dict | None:
    quoted = payload.get("quoted_tweet")
    if quoted:
        return {"kind": "quote", "post": _context_post(quoted)}
    parent = payload.get("parent")
    if parent or payload.get("in_reply_to_status_id_str"):
        return {"kind": "reply", "post": _context_post(parent or _bare_parent(payload))}
    return None


def _bare_parent(payload: dict) -> dict:
    return {
        "id_str": payload.get("in_reply_to_status_id_str"),
        "text": None,
        "user": {"screen_name": payload.get("in_reply_to_screen_name")},
        "created_at": payload.get("created_at"),
    }


def _context_post(payload: dict) -> dict:
    user = payload.get("user") or {}
    handle = user.get("screen_name") or "x"
    return {
        "id": f"x/{payload.get('id_str')}",
        "network": "x",
        "author": {"handle": handle, "name": user.get("name") or handle},
        "permalink": f"{HOME}/{handle}/status/{payload.get('id_str')}",
        "posted_at": iso(datetime.fromisoformat(payload["created_at"])),
        "text": (payload.get("text") or "").strip() or None,
        "media": [],
        "video": None,
        "stats": {
            "likes": payload.get("favorite_count"),
            "reposts": payload.get("retweet_count"),
            "replies": payload.get("reply_count"),
        },
    }


def _replies(tab, post: Post) -> list[dict]:
    """The first replies under a post, as the permalink page draws them; the post itself is the first article."""
    try:
        tab.goto(post.permalink)
        tab.wait_for_selector('article[data-testid="tweet"]', timeout=20)
    except Exception as error:
        raise SourceFailure(f"the replies of {post.id} did not load: {error}") from error
    return tab.eval(REPLIES) or []


REPLIES = """[...document.querySelectorAll('article[data-testid="tweet"]')].slice(1, 4).map(a => {
    const text = a.querySelector('[data-testid="tweetText"]');
    const link = a.querySelector('a[href*="/status/"]');
    const author = a.querySelector('[data-testid="User-Name"]');
    let handle = null;
    if (author) {
        const profile = [...author.querySelectorAll('a[href]')].map(l => l.getAttribute('href') || '')
            .find(h => /^https:\\/\\/x\\.com\\/[A-Za-z0-9_]+\\/?$/.test(h));
        const found = (profile || '').match(/x\\.com\\/([A-Za-z0-9_]+)/) || author.innerText.match(/@([A-Za-z0-9_]+)/);
        if (found) handle = found[1];
    }
    return {
        author: author ? author.innerText.split("\\n")[0].trim() : "",
        handle: handle,
        text: text ? text.innerText.trim() : null,
        permalink: link ? link.href : null,
    };
}).filter(reply => reply.text)"""

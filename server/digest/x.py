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
from digest.reading import SourceFailure, SourceResult, save_photo
from digest.store import Post, iso
from web import Web

HOME = "https://x.com"
SYNDICATION = "https://cdn.syndication.twimg.com/tweet-result"
STATUS = re.compile(r"/status/(\d+)")
REQUEST_PAUSE = 0.4
TOP_DISCUSSED = 3


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    if page is None:
        raise SourceFailure("X needs the logged-in profile")
    handle = source["handle"]
    report(f"reading x.com/{handle}")
    ids = _timeline(page, handle)
    posts: list[Post] = []
    note = None
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
        post = _post(payload, handle, source, web, store, folders)
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


def _timeline(page, handle: str) -> list[str]:
    """The status ids on the profile timeline, in the order the page shows them, newest first."""
    try:
        page.goto(f"{HOME}/{handle}", wait_until="domcontentloaded", timeout=45_000)
        if "/login" in page.url or "/i/flow/login" in page.url:
            raise SourceFailure("the login expired; run python -m digest.login x")
        page.wait_for_selector('[data-testid="tweet"]', timeout=20_000)
    except SourceFailure:
        raise
    except Exception as error:
        raise SourceFailure(f"x.com/{handle} did not show its timeline: {error}") from error
    pattern = re.compile(rf"/{re.escape(handle)}/status/(\d+)", re.IGNORECASE)
    seen: list[str] = []
    for _ in range(4):
        hrefs = page.eval_on_selector_all('a[href*="/status/"]', "els => els.map(e => e.getAttribute('href'))") or []
        for href in hrefs:
            match = pattern.match(href)
            if match and match.group(1) not in seen:
                seen.append(match.group(1))
        page.mouse.wheel(0, 1400)
        page.wait_for_timeout(900)
    return seen


def _tweet(web: Web, status_id: str) -> dict | None:
    payload = json.loads(web.text(f"{SYNDICATION}?id={status_id}&token=a&lang=en"))
    return payload if payload.get("__typename") == "Tweet" else None


def _post(payload: dict, handle: str, source: dict, web: Web, store, folders: list[str]) -> Post | None:
    status_id = payload.get("id_str")
    if not status_id:
        return None
    user = payload.get("user") or {}
    author = {
        "handle": user.get("screen_name") or handle,
        "name": user.get("name") or handle,
    }
    post_id = f"x/{status_id}"
    text = (payload.get("text") or "").strip() or None
    media, video = _media(payload, post_id, web, store)
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
        permalink=f"{HOME}/{author['handle']}/status/{status_id}",
        posted_at=iso(datetime.fromisoformat(payload["created_at"])),
        text=text,
        media=media,
        video=video,
        context=_context(payload),
        stats=stats,
        folders=folders,
    )


def _media(payload: dict, post_id: str, web: Web, store) -> tuple[list[dict], dict | None]:
    media: list[dict] = []
    video = None
    for index, item in enumerate((payload.get("mediaDetails") or [])[:4]):
        kind = item.get("type")
        url = item.get("media_url_https")
        if not url:
            continue
        if kind == "photo":
            saved = save_photo(web, store, post_id, index, f"{url}?name=large")
            if saved:
                media.append(saved)
        elif kind in ("video", "animated_gif") and video is None:
            poster = save_photo(web, store, post_id, "poster", url)
            video = {"poster": poster, "duration": _duration(payload)}
    return media, video


def _duration(payload: dict) -> float | None:
    time_ms = (payload.get("video") or {}).get("durationMs")
    return time_ms / 1000 if time_ms else None


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


def _replies(page, post: Post) -> list[dict]:
    """The first replies under a post, as the permalink page draws them; the post itself is the first article."""
    try:
        page.goto(post.permalink, wait_until="domcontentloaded", timeout=45_000)
        page.wait_for_selector('article[data-testid="tweet"]', timeout=20_000)
    except Exception as error:
        raise SourceFailure(f"the replies of {post.id} did not load: {error}") from error
    comments = []
    for article in page.query_selector_all('article[data-testid="tweet"]')[1:4]:
        text = article.query_selector('[data-testid="tweetText"]')
        if text is None:
            continue
        link = article.query_selector('a[href*="/status/"]')
        href = link.get_attribute("href") if link else None
        author = article.query_selector('[data-testid="User-Name"]')
        label = author.inner_text().split("\n")[0].strip() if author else ""
        comments.append({
            "author": label,
            "text": text.inner_text().strip(),
            "permalink": f"{HOME}{href}" if href else None,
        })
    return comments

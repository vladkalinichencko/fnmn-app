"""Instagram posts. The profile grid of the logged-in profile gives the links of recent posts; each new post is
opened once for its caption, its picture and its time. Instagram checks automation harder than the other two
networks, so a run reads a small number of new posts and leaves the rest for the next one."""

from __future__ import annotations

import re
from datetime import datetime, timezone

from lxml import html

from package import Report
from digest.sources import SourceFailure, SourceResult, save_photo
from digest.store import Post, iso
from web import Web

HOME = "https://www.instagram.com"
SHORTCODE = re.compile(r"/(p|reel)/([A-Za-z0-9_-]+)")
MAX_POSTS = 8


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    if page is None:
        raise SourceFailure("Instagram needs the logged-in profile")
    handle = source["handle"]
    report(f"reading instagram.com/{handle}")
    links = _grid(page, handle)
    known = store.ids()
    posts: list[Post] = []
    name = None
    for shortcode in links:
        post_id = f"instagram/{handle}/{shortcode}"
        if post_id in known:
            continue
        if len(posts) >= MAX_POSTS:
            break
        post = _post(page, handle, shortcode, source, web, store, folders)
        if post is not None:
            posts.append(post)
            name = name or post.author["name"]
        page.wait_for_timeout(1200)
    note = None
    if len(posts) >= MAX_POSTS:
        note = f"read the first {MAX_POSTS} new posts; the rest wait for the next run"
    return SourceResult(posts=sorted(posts, key=lambda post: post.posted_at), name=name, note=note)


def _grid(page, handle: str) -> list[str]:
    try:
        page.goto(f"{HOME}/{handle}/", wait_until="domcontentloaded", timeout=45_000)
        if "/accounts/login" in page.url:
            raise SourceFailure("the login expired; run python -m digest.login instagram")
        page.wait_for_selector('a[href*="/p/"], a[href*="/reel/"]', timeout=20_000)
    except SourceFailure:
        raise
    except Exception as error:
        raise SourceFailure(f"instagram.com/{handle} did not show its profile: {error}") from error
    found: list[str] = []
    for _ in range(2):
        hrefs = page.eval_on_selector_all('a[href*="/p/"], a[href*="/reel/"]', "els => els.map(e => e.getAttribute('href'))") or []
        for href in hrefs:
            match = SHORTCODE.search(href or "")
            if match and match.group(2) not in found:
                found.append(match.group(2))
        page.mouse.wheel(0, 1200)
        page.wait_for_timeout(900)
    return found


def _post(page, handle: str, shortcode: str, source: dict, web: Web, store, folders: list[str]) -> Post | None:
    """One post page: the caption and the picture are in the page's own meta tags, the time in its `time`."""
    try:
        page.goto(f"{HOME}/p/{shortcode}/", wait_until="domcontentloaded", timeout=45_000)
        markup = page.content()
    except Exception:
        return None
    document = html.fromstring(markup)
    caption = _meta(document, "og:description")
    image = _meta(document, "og:image")
    title = _meta(document, "og:title") or handle
    post_id = f"instagram/{handle}/{shortcode}"
    media = []
    if image:
        saved = save_photo(web, store, post_id, 0, image)
        if saved:
            media.append(saved)
    times = document.xpath("//time/@datetime")
    posted = iso(datetime.fromisoformat(times[0])) if times else iso(datetime.now(timezone.utc))
    return Post(
        id=post_id,
        network="instagram",
        source=source["id"],
        author={"handle": handle, "name": title},
        permalink=f"{HOME}/p/{shortcode}/",
        posted_at=posted,
        text=_caption(caption),
        media=media,
        folders=folders,
    )


def _meta(document, property_name: str) -> str | None:
    values = document.xpath(f'//meta[@property="{property_name}"]/@content')
    return values[0] if values else None


def _caption(description: str | None) -> str | None:
    """`og:description` reads like `1,234 likes, 56 comments - name on March 3, 2026: "the caption"`; the
    caption is what follows the opening quote."""
    if not description:
        return None
    marker = description.find(': "')
    if marker < 0:
        return description.strip() or None
    text = description[marker + 3:]
    return text.rstrip('"').strip() or None

"""Instagram posts. The profile grid of the logged-in profile gives the links of recent posts; each new post is
opened once for its caption, its picture and its time. Instagram checks automation harder than the other two
networks, so a run reads a small number of new posts and leaves the rest for the next one."""

from __future__ import annotations

import re
from datetime import datetime

from lxml import html

from package import Report
from digest.reading import SourceFailure, SourceResult, page_fetch, save_photo, save_video
from digest.store import Post, iso
from web import Web

HOME = "https://www.instagram.com"
SHORTCODE = re.compile(r"/(p|reel)/([A-Za-z0-9_-]+)")
MAX_POSTS = 8


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    if page is None:
        raise SourceFailure("Instagram needs the logged-in profile")
    if source.get("scope") == "recommendations":
        report("reading the home feed")
        links = _feed(page)
    else:
        handle = source["handle"]
        report(f"reading instagram.com/{handle}")
        links = [(shortcode, handle) for shortcode in _grid(page, handle)]
    known = store.ids()
    posts: list[Post] = []
    name = None
    skipped = 0
    for shortcode, author in links:
        post_id = f"instagram/{author}/{shortcode}"
        if post_id in known:
            continue
        if len(posts) >= MAX_POSTS:
            break
        post = _post(page, author, shortcode, source, web, store, folders)
        if post is not None:
            posts.append(post)
            name = name or post.author["name"]
        else:
            skipped += 1
        page.wait_for_timeout(1200)
    notes = []
    if len(posts) >= MAX_POSTS:
        notes.append(f"read the first {MAX_POSTS} new posts; the rest wait for the next run")
    if skipped:
        notes.append(f"{skipped} posts had no time to place them")
    return SourceResult(
        posts=sorted(posts, key=lambda post: post.posted_at),
        name=name,
        note="; ".join(notes) or None,
    )


def _grid(tab, handle: str) -> list[str]:
    try:
        tab.goto(f"{HOME}/{handle}/")
        if "/accounts/login" in tab.url:
            raise SourceFailure("the login expired; run python -m digest.login instagram")
        tab.wait_for_selector('a[href*="/p/"], a[href*="/reel/"]', timeout=20)
    except SourceFailure:
        raise
    except Exception as error:
        raise SourceFailure(f"instagram.com/{handle} did not show its profile: {error}") from error
    found: list[str] = []
    for _ in range(2):
        hrefs = tab.eval_on_selector_all('a[href*="/p/"], a[href*="/reel/"]', "e => e.getAttribute('href')") or []
        for href in hrefs:
            match = SHORTCODE.search(href or "")
            if match and match.group(2) not in found:
                found.append(match.group(2))
        tab.wheel(1200)
        tab.wait_for_timeout(900)
    return found


def _feed(tab) -> list[tuple[str, str]]:
    """(shortcode, author handle) pairs from the home feed; a post whose author the page does not name
    is dropped, since its id and its card both need one."""
    try:
        tab.goto(f"{HOME}/")
        if "/accounts/login" in tab.url:
            raise SourceFailure("the login expired; run python -m digest.login instagram")
        tab.wait_for_selector('a[href*="/p/"], a[href*="/reel/"]', timeout=20)
    except SourceFailure:
        raise
    except Exception as error:
        raise SourceFailure(f"the home feed did not load: {error}") from error
    pairs: list[tuple[str, str]] = []
    seen: set[str] = set()
    for _ in range(2):
        rows = tab.eval_on_selector_all('a[href*="/p/"], a[href*="/reel/"]', FEED_AUTHOR) or []
        for code, user in _pairs(rows):
            if code not in seen:
                seen.add(code)
                pairs.append((code, user))
        tab.wheel(1200)
        tab.wait_for_timeout(900)
    return pairs


def _pairs(rows) -> list[tuple[str, str]]:
    """The feed rows the page script returned, as (shortcode, author) pairs without the noise."""
    found = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        match = SHORTCODE.search(row.get("href") or "")
        user = (row.get("user") or "").strip("/")
        if match and user and user.lower() not in RESERVED:
            found.append((match.group(2), user))
    return found


FEED_AUTHOR = """e => {
  const article = e.closest('article');
  const link = article ? [...article.querySelectorAll('a[href^="/"]')]
    .find(l => /^\\/[A-Za-z0-9._]+\\/?$/.test(l.getAttribute('href') || '')) : null;
  return {href: e.getAttribute('href'), user: link ? link.getAttribute('href') : null};
}"""

RESERVED = {"", "explore", "reels", "stories", "direct", "accounts", "p", "reel"}


def _post(tab, handle: str, shortcode: str, source: dict, web: Web, store, folders: list[str]) -> Post | None:
    """One post page: the caption and the picture are in the page's own meta tags, the time in its `time`."""
    try:
        tab.goto(f"{HOME}/p/{shortcode}/")
        markup = tab.html()
    except Exception:
        return None
    document = html.fromstring(markup)
    caption = _meta(document, "og:description")
    image = _meta(document, "og:image")
    title = _meta(document, "og:title") or handle
    post_id = f"instagram/{handle}/{shortcode}"
    media = []
    errors = 0
    fetch = page_fetch(tab)
    dom = _dom_media(tab)
    images = dom["images"] or ([image] if image else [])
    for index, url in enumerate(images):
        saved = save_photo(web, store, post_id, index, url, fetch)
        if saved:
            media.append(saved)
        else:
            errors += 1
    video_urls = dom["videos"] or [
        url for url in (_meta(document, "og:video:secure_url"), _meta(document, "og:video")) if url
    ]
    video = None
    if video_urls:
        video_file = save_video(web, store, post_id, "video", video_urls[0], fetch)
        poster = media[0] if media else (save_photo(web, store, post_id, "poster", image, fetch) if image else None)
        video = {"poster": poster, "file": video_file}
        if video_file is None and poster is None:
            errors += 1
    times = document.xpath("//time/@datetime")
    if not times:
        return None
    posted = iso(datetime.fromisoformat(times[0]))
    return Post(
        id=post_id,
        network="instagram",
        source=source["id"],
        author={"handle": handle, "name": title},
        permalink=f"{HOME}/p/{shortcode}/",
        posted_at=posted,
        text=_caption(caption),
        media=media,
        video=video,
        folders=folders,
        media_errors=errors,
    )


def _dom_media(tab) -> dict:
    """The post's own attachments from the rendered page: carousel frames at their largest srcset
    size and any playable video URL. Empty lists mean the page kept them out of the DOM."""
    try:
        found = tab.eval(DOM_MEDIA) or {}
    except Exception:
        return {"images": [], "videos": []}
    return {
        "images": [url for url in found.get("images") or [] if isinstance(url, str)],
        "videos": [url for url in found.get("videos") or [] if isinstance(url, str)],
    }


DOM_MEDIA = """(() => {
  const images = new Set(), videos = new Set();
  const big = url => {
    const size = url.match(/s(\\d+)x(\\d+)/);
    return !size || Math.max(+size[1], +size[2]) >= 480;
  };
  const isPostImage = url => typeof url === 'string' && url.includes('cdninstagram.com')
    && !url.includes('s150x150') && big(url);
  const best = img => {
    let top = null, topW = 0;
    for (const part of (img.getAttribute('srcset') || '').split(',')) {
      const [url, width] = part.trim().split(/\\s+/);
      if (url && (+width || 0) >= topW) { top = url; topW = +width || 0; }
    }
    return top || img.currentSrc || img.src;
  };
  document.querySelectorAll('main img, article img, [role="main"] img').forEach(img => {
    const url = best(img);
    if (isPostImage(url)) images.add(url);
  });
  document.querySelectorAll('video').forEach(v => {
    const source = v.querySelector('source');
    const url = v.currentSrc || v.src || (source && source.src);
    if (typeof url === 'string' && url.startsWith('http')) videos.add(url);
  });
  return {images: [...images], videos: [...videos]};
})()"""


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

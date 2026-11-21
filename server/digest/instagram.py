"""Instagram posts. The profile grid of the logged-in profile gives the links of recent posts; each new post is
opened once for its caption, its picture and its time. Instagram checks automation harder than the other two
networks, so a run reads a small number of new posts and leaves the rest for the next one."""

from __future__ import annotations

import json
import re
from datetime import datetime

from lxml import html

from package import Report
from digest.reading import SourceFailure, SourceResult, page_fetch, save_photo, save_video
from digest.store import Post, iso
from web import Web

HOME = "https://www.instagram.com"
LINK = re.compile(r"/(?:([A-Za-z0-9._]+)/)?(p|reel)/([A-Za-z0-9_-]+)")
MAX_POSTS = 8


def _link(href: str | None) -> tuple[str | None, str, str] | None:
    """A post href as (author, kind, shortcode): `/handle/p/code/` names its author, a bare
    `/p/code/` does not."""
    match = LINK.search(href or "")
    if not match:
        return None
    return match.group(1), match.group(2), match.group(3)


def collect(source: dict, web: Web, store, folders: list[str], report: Report, page=None) -> SourceResult:
    if page is None:
        raise SourceFailure("Instagram needs the logged-in profile")
    if source.get("scope") == "recommendations":
        report("reading the home feed")
        links = _feed(page)
    else:
        handle = source["handle"]
        report(f"reading instagram.com/{handle}")
        links = _grid(page, handle)
    known = store.ids()
    posts: list[Post] = []
    name = None
    skipped = 0
    for author, kind, shortcode in links:
        post_id = f"instagram/{shortcode}"
        if post_id in known:
            continue
        if len(posts) >= MAX_POSTS:
            break
        post = _post(page, author, kind, shortcode, source, web, store, folders)
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


def _grid(tab, handle: str) -> list[tuple[str, str, str]]:
    """(author, kind, shortcode) of the profile's posts, in the order the grid shows them."""
    try:
        tab.goto(f"{HOME}/{handle}/")
        if "/accounts/login" in tab.url:
            raise SourceFailure("the login expired; run python -m digest.login instagram")
        tab.wait_for_selector('a[href*="/p/"], a[href*="/reel/"]', timeout=20)
    except SourceFailure:
        raise
    except Exception as error:
        raise SourceFailure(f"instagram.com/{handle} did not show its profile: {error}") from error
    found: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for _ in range(2):
        hrefs = tab.eval_on_selector_all('a[href*="/p/"], a[href*="/reel/"]', "e => e.getAttribute('href')") or []
        for href in hrefs:
            link = _link(href)
            if link and link[2] not in seen:
                seen.add(link[2])
                found.append((link[0] or handle, link[1], link[2]))
        tab.wheel(1200)
        tab.wait_for_timeout(900)
    return found


def _feed(tab) -> list[tuple[str, str, str]]:
    """(author, kind, shortcode) of the home feed's posts; a post whose author the page does not name
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
    pairs: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for _ in range(2):
        rows = tab.eval_on_selector_all('a[href*="/p/"], a[href*="/reel/"]', FEED_AUTHOR) or []
        for row in _pairs(rows):
            if row[2] not in seen:
                seen.add(row[2])
                pairs.append(row)
        tab.wheel(1200)
        tab.wait_for_timeout(900)
    return pairs


def _pairs(rows) -> list[tuple[str, str, str]]:
    """The feed rows the page script returned, as (author, kind, shortcode) without the noise."""
    found = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        link = _link(row.get("href"))
        user = (row.get("user") or "").strip("/")
        if link and user and user.lower() not in RESERVED:
            found.append((user, link[1], link[2]))
    return found


FEED_AUTHOR = """e => {
  const article = e.closest('article');
  const link = article ? [...article.querySelectorAll('a[href^="/"]')]
    .find(l => /^\\/[A-Za-z0-9._]+\\/?$/.test(l.getAttribute('href') || '')) : null;
  return {href: e.getAttribute('href'), user: link ? link.getAttribute('href') : null};
}"""

RESERVED = {"", "explore", "reels", "stories", "direct", "accounts", "p", "reel"}


def _post(tab, handle: str, kind: str, shortcode: str, source: dict, web: Web, store, folders: list[str]) -> Post | None:
    """One post page: the caption and the picture are in the page's own meta tags, the time in its `time`,
    and the attachments in the embedded `xdt_shortcode_media` JSON, in the carousel's own order. The URL
    names its author — the bare `/p/` form answers a rate-limited error page to the logged-in browser,
    while `/{handle}/p/` loads; the page itself names the owner again, since a feed guess can be wrong."""
    permalink = f"{HOME}/{handle}/{kind}/{shortcode}/"
    try:
        tab.goto(permalink)
        if "/accounts/login" in tab.url:
            raise SourceFailure("the login expired; run python -m digest.login instagram")
        markup = tab.html()
        if "/p/" in tab.url or "/reel/" in tab.url:
            permalink = tab.url.split("?")[0]
    except SourceFailure:
        raise
    except Exception:
        return None
    document = html.fromstring(markup)
    caption = _meta(document, "og:description")
    title = _meta(document, "og:title") or handle
    owner = _owner(markup) or handle
    post_id = f"instagram/{shortcode}"
    attachments = []
    errors = 0
    fetch = page_fetch(tab)
    for attachment in _attachments(markup, document, post_id, web, store, fetch, tab):
        if attachment is None:
            errors += 1
        else:
            attachments.append(attachment)
    times = document.xpath("//time/@datetime")
    if not times:
        return None
    posted = iso(datetime.fromisoformat(times[0]))
    return Post(
        id=post_id,
        network="instagram",
        source=source["id"],
        author={"handle": owner, "name": title},
        permalink=permalink,
        posted_at=posted,
        text=_caption(caption),
        attachments=attachments,
        folders=folders,
        media_errors=errors,
    )


def _attachments(markup: str, document, post_id: str, web: Web, store, fetch, tab) -> list[dict | None]:
    """The post's media in order. The embedded JSON knows each carousel child's kind and video address;
    without it the page's own DOM and og tags stand in, as before."""
    node = _shortcode_node(markup)
    if node is not None:
        return [
            _save_attachment(web, store, post_id, index, spec, fetch)
            for index, spec in enumerate(_media_specs(node))
        ]
    specs = _fallback_specs(markup, document, tab)
    return [
        _save_attachment(web, store, post_id, index, spec, fetch)
        for index, spec in enumerate(specs)
    ]


def _media_specs(node: dict) -> list[dict]:
    """Each media child of the post as {"kind", "image", "video"} URLs: a carousel's children in order,
    the post itself when it is not a carousel."""
    children = node.get("edge_sidecar_to_children", {}).get("edges") or []
    items = [edge["node"] for edge in children if isinstance(edge.get("node"), dict)]
    media = node.get("carousel_media")
    if not items and isinstance(media, list):
        items = [item for item in media if isinstance(item, dict)]
    if not items:
        items = [node]
    specs = []
    for item in items:
        video = _best_video(item)
        image = _best_image(item)
        if item.get("is_video") or video:
            specs.append({"kind": "video", "image": image, "video": video})
        elif image:
            specs.append({"kind": "image", "image": image})
    return specs


def _fallback_specs(markup: str, document, tab) -> list[dict]:
    """Media the embedded JSON did not give: DOM images first, then the first playable video, then the
    og tags — the order the old reader produced."""
    image = _meta(document, "og:image")
    dom = _dom_media(tab)
    specs = [{"kind": "image", "image": url} for url in (dom["images"] or ([image] if image else []))]
    page_video = _page_video(markup)
    video_urls = dom["videos"] or ([page_video] if page_video else []) or [
        url for url in (_meta(document, "og:video:secure_url"), _meta(document, "og:video")) if url
    ]
    if video_urls:
        specs.append({"kind": "video", "image": image, "video": video_urls[0]})
    return specs


def _save_attachment(web: Web, store, post_id: str, index: int, spec: dict, fetch) -> dict | None:
    if spec["kind"] == "image":
        if not spec.get("image"):
            return None
        saved = save_photo(web, store, post_id, index, spec["image"], fetch)
        return {"kind": "image", **saved} if saved else None
    video_file = save_video(web, store, post_id, f"{index}-video", spec["video"], fetch) if spec.get("video") else None
    poster = save_photo(web, store, post_id, f"{index}-poster", spec["image"], fetch) if spec.get("image") else None
    if video_file is None and poster is None:
        return None
    return {"kind": "video", "file": video_file, "poster": poster}


def _shortcode_node(markup: str) -> dict | None:
    """The post's `xdt_shortcode_media` object out of the page's embedded JSON; the page writes it with
    HTML-escaped quotes, which the decoder reads back as they were."""
    text = markup.replace("&quot;", '"')
    at = text.find('"xdt_shortcode_media"')
    if at < 0:
        return None
    start = text.find("{", at)
    if start < 0:
        return None
    try:
        node, _ = json.JSONDecoder().raw_decode(text[start:])
    except json.JSONDecodeError:
        return None
    return node if isinstance(node, dict) else None


def _owner(markup: str) -> str | None:
    """The username the post's own JSON names as owner; a feed's first profile-looking link can belong
    to a neighbour post, so the page is the authority."""
    text = markup.replace("&quot;", '"')
    match = re.search(r'"owner"\s*:\s*\{[^{}]*?"username"\s*:\s*"([^"]+)"', text)
    return match.group(1) if match else None


def _best_image(item: dict) -> str | None:
    candidates = (item.get("image_versions2") or {}).get("candidates") or []
    best_url, best_area = None, 0
    for candidate in candidates:
        url = candidate.get("url")
        if not url:
            continue
        area = (candidate.get("width") or 0) * (candidate.get("height") or 0)
        if area > best_area:
            best_url, best_area = url, area
    return best_url or item.get("display_url")


def _best_video(item: dict) -> str | None:
    versions = item.get("video_versions") or []
    best_url, best_area = None, 0
    for version in versions:
        url = version.get("url")
        if not url:
            continue
        area = (version.get("width") or 0) * (version.get("height") or 0)
        if area > best_area:
            best_url, best_area = url, area
    if best_url is not None:
        return _unescape(best_url)
    video_url = item.get("video_url")
    return _unescape(video_url) if video_url else None


def _page_video(markup: str) -> str | None:
    """The post's mp4 as the page's embedded JSON names it: the player keeps its `video` element
    empty until it plays, so the DOM and the og tags often carry no fetchable address. The first
    `video_versions` block is the first attachment's, the order the carousel shows them in."""
    text = markup.replace("&quot;", '"')
    block = re.search(r'"video_versions"\s*:\s*\[', text)
    if block:
        section = text[block.end():block.end() + 40000]
        end = section.find("]")
        if end > 0:
            section = section[:end]
        best_url, best_area = None, 0
        for item in re.findall(r"\{[^{}]*\}", section):
            url = _json_string(item, "url")
            if url is None:
                continue
            area = _json_int(item, "width") * _json_int(item, "height")
            if area > best_area:
                best_url, best_area = url, area
        if best_url is not None:
            return best_url
    match = re.search(r'"video_url"\s*:\s*"((?:[^"\\]|\\.)*)"', text)
    return _unescape(match.group(1)) if match else None


def _json_string(item: str, name: str) -> str | None:
    match = re.search(rf'"{name}"\s*:\s*"((?:[^"\\]|\\.)*)"', item)
    return _unescape(match.group(1)) if match else None


def _json_int(item: str, name: str) -> int:
    match = re.search(rf'"{name}"\s*:\s*(\d+)', item)
    return int(match.group(1)) if match else 0


def _unescape(raw: str) -> str:
    try:
        return json.loads(f'"{raw}"').replace("&amp;", "&")
    except json.JSONDecodeError:
        return raw.replace("\\/", "/").replace("&amp;", "&")


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
    caption is what follows the opening quote. Without the quote the description is only the counts —
    a media-only post has no caption, and the counts are not one."""
    if not description:
        return None
    marker = description.find(': "')
    if marker < 0:
        return None
    text = description[marker + 3:]
    return text.rstrip('"').strip() or None

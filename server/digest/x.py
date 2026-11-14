"""X posts. The timeline page of the logged-in profile gives the ids of recent posts; the public syndication
endpoint then returns each post's full JSON, media sizes and quoted or answered post included, without a second
page load. A reply's ancestors are read from its permalink page — the page is the only place the whole chain
above the post is drawn — and each ancestor is hydrated through the same syndication endpoint, so the store
keeps every message of the chain as a post of its own. Replies of the few most discussed posts are read from
the permalink page while it is still open.
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
CHAIN_LIMIT = 5
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
    seen: set[str] = set()
    note = None
    fetch = page_fetch(page)
    for status_id in ids:
        try:
            payload = _tweet(web, status_id)
            entry = _entry(payload, handle, source, web, store, folders, fetch, page) if payload else []
        except httpx.HTTPStatusError as error:
            if error.response.status_code == 429:
                note = "X rate-limited the reader"
                break
            continue
        except OSError:
            note = "x.com stopped answering"
            break
        for post in entry:
            if post.id not in seen:
                seen.add(post.id)
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


def _permalink(payload: dict) -> str:
    user = payload.get("user") or {}
    handle = user.get("screen_name") or "x"
    return f"{HOME}/{handle}/status/{payload['id_str']}"


def _reply_parent_id(payload: dict) -> str | None:
    parent = payload.get("parent") or {}
    return payload.get("in_reply_to_status_id_str") or parent.get("id_str")


def _note_full(payload: dict) -> str | None:
    """The whole body when the payload itself carries it; the syndication endpoint usually keeps only
    the note's id, in which case the permalink page is the full version's only source."""
    note = payload.get("note_tweet")
    if not isinstance(note, dict):
        return None
    for candidate in (note.get("full_text"), (note.get("note_tweet_results") or {}).get("result", {}).get("text")):
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
    return None


def _payload_text(payload: dict) -> str | None:
    return _note_full(payload) or ((payload.get("text") or "").strip() or None)


def _entry(payload: dict, handle: str, source: dict, web: Web, store, folders: list[str], fetch, page) -> list[Post]:
    """The post plus the ancestors its reply chain needs, each a full post of its own. The chain comes
    off the permalink page, root first; every id is then hydrated through the syndication endpoint, so
    an ancestor keeps its media, stats and whole text. A post whose parent could not be read keeps a
    reply context with no post, which the card draws as 'a post that is gone'."""
    status_id = payload.get("id_str")
    if not status_id:
        return []
    reply_to = _reply_parent_id(payload)
    needs_page = reply_to is not None or (payload.get("note_tweet") and _note_full(payload) is None)
    ancestor_ids: list[str] = []
    focal_text = None
    if page is not None and needs_page:
        ancestor_ids, focal_text = _conversation(page, _permalink(payload), status_id)
    truncated = len(ancestor_ids) > CHAIN_LIMIT
    chain: list[tuple[Post, dict]] = []
    fetched: dict[str, Post] = {}
    for ancestor_id in ancestor_ids[-CHAIN_LIMIT:]:
        try:
            ancestor = _tweet(web, ancestor_id)
        except (httpx.HTTPStatusError, OSError):
            continue
        if ancestor is None or not ancestor.get("id_str"):
            continue
        own = (ancestor.get("user") or {}).get("screen_name") or "x"
        post = _post(ancestor, own, source, web, store, folders, fetch=fetch)
        if post is None:
            continue
        if ancestor.get("note_tweet") and _note_full(ancestor) is None and page is not None:
            text = _note_text(page, _permalink(ancestor), ancestor_id)
            if text:
                post.text = text
        chain.append((post, ancestor))
        fetched[post.id] = post
    focal = _post(payload, handle, source, web, store, folders, fetch=fetch)
    if focal is None:
        return [post for post, _ in chain]
    if payload.get("note_tweet") and focal_text:
        focal.text = focal_text
    items = chain + [(focal, payload)]
    for post, item in items:
        post.context = _wired_context(item, fetched)
    if truncated and chain:
        first, _ = chain[0]
        context = first.context
        if context and context["kind"] == "reply" and context["post"] is None:
            first.context = None
    return [post for post, _ in items]


def _conversation(tab, permalink: str, focal_id: str) -> tuple[list[str], str | None]:
    """The status ids above the focal post on its permalink page, root first, and the focal post's own
    text as the page draws it. A page that will not show the conversation reads as an empty chain."""
    try:
        tab.goto(permalink)
        tab.wait_for_selector('article[data-testid="tweet"]', timeout=20)
        tab.wait_for_timeout(600)
        found = tab.eval(CONVERSATION.replace("__FOCAL__", json.dumps(focal_id)))
    except Exception:
        return [], None
    if not isinstance(found, dict):
        return [], None
    ancestors = [item for item in found.get("ancestors") or [] if isinstance(item, str)]
    text = found.get("text")
    return ancestors, text.strip() if isinstance(text, str) and text.strip() else None


CONVERSATION = """(() => {
  const focal = __FOCAL__;
  const articles = [...document.querySelectorAll('article[data-testid="tweet"]')];
  const own = article => {
    const timed = [...article.querySelectorAll('a[href*="/status/"]')].filter(link => link.querySelector('time'));
    const link = timed[timed.length - 1];
    const match = link && (link.getAttribute('href') || '').match(/status\\/(\\d+)/);
    return match ? match[1] : null;
  };
  const at = articles.findIndex(article => own(article) === focal);
  const ancestors = at > 0 ? articles.slice(0, at).map(own).filter(Boolean) : [];
  const text = at >= 0 ? articles[at].querySelector('[data-testid="tweetText"]') : null;
  return {ancestors, text: text ? text.innerText : null};
})()"""


def _wired_context(payload: dict, fetched: dict[str, Post]) -> dict | None:
    """The context a collected post carries: a quote stays the payload's own summary, a reply points at
    the ancestor post this run fetched — or at nothing when the parent is gone, protected or beyond the
    chain's limit."""
    quoted = payload.get("quoted_tweet")
    if quoted:
        return {"kind": "quote", "post": _context_post(quoted)}
    parent_id = _reply_parent_id(payload)
    if not parent_id:
        return None
    parent = fetched.get(f"x/{parent_id}")
    return {"kind": "reply", "post": _context_of(parent) if parent else None}


def _context_of(post: Post) -> dict:
    """A stored post as the context summary the package carries: its whole text, no media — the files of
    a context post are not part of the delivery, the card shows the words only."""
    return {
        "id": post.id,
        "network": post.network,
        "author": post.author,
        "permalink": post.permalink,
        "posted_at": post.posted_at,
        "text": post.text,
        "media": [],
        "video": None,
        "stats": post.stats,
    }


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
    permalink = _permalink(payload)
    text = _payload_text(payload)
    if payload.get("note_tweet") and _note_full(payload) is None and page is not None:
        text = _note_text(page, permalink, status_id) or text
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


NOTE_TEXT = """id => {
    const article = [...document.querySelectorAll('article[data-testid="tweet"]')].find(a => {
        const timed = [...a.querySelectorAll('a[href*="/status/"]')].filter(link => link.querySelector('time'));
        const link = timed[timed.length - 1];
        return link && (link.getAttribute('href') || '').includes('/status/' + id);
    });
    const text = article && article.querySelector('[data-testid="tweetText"]');
    return text ? text.innerText : null;
}"""


def _note_text(tab, permalink: str, status_id: str) -> str | None:
    """A long post's whole body: the syndication payload carries only a preview of it. The read is scoped
    to the post's own article — a reply's permalink draws the whole chain above it, and the first text on
    the page belongs to the root ancestor, not to the post."""
    try:
        tab.goto(permalink)
        tab.wait_for_selector('article[data-testid="tweet"]', timeout=20)
        text = tab.eval(f"({NOTE_TEXT})({json.dumps(status_id)})")
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
        "text": _payload_text(payload),
        "media": [],
        "video": None,
        "stats": {
            "likes": payload.get("favorite_count"),
            "reposts": payload.get("retweet_count"),
            "replies": payload.get("reply_count"),
        },
    }


def _replies(tab, post: Post) -> list[dict]:
    """The first replies under a post, as the permalink page draws them; on a reply's page the articles
    above the post are its ancestors, so the replies are the articles after the post's own."""
    try:
        tab.goto(post.permalink)
        tab.wait_for_selector('article[data-testid="tweet"]', timeout=20)
    except Exception as error:
        raise SourceFailure(f"the replies of {post.id} did not load: {error}") from error
    status_id = post.id.rsplit("/", 1)[-1]
    return tab.eval(REPLIES.replace("__FOCAL__", json.dumps(status_id))) or []


REPLIES = """(() => {
    const focal = __FOCAL__;
    const own = article => {
        const timed = [...article.querySelectorAll('a[href*="/status/"]')].filter(link => link.querySelector('time'));
        const link = timed[timed.length - 1];
        const match = link && (link.getAttribute('href') || '').match(/status\\/(\\d+)/);
        return match ? match[1] : null;
    };
    const articles = [...document.querySelectorAll('article[data-testid="tweet"]')];
    const at = articles.findIndex(article => own(article) === focal);
    return articles.slice(at < 0 ? 1 : at + 1, (at < 0 ? 1 : at + 1) + 3).map(a => {
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
}).filter(reply => reply.text);
})()"""

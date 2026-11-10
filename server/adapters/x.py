"""X posts and threads. The public syndication CDN returns a post's full JSON — text, author, photos, video,
quoted post, and the post it answers — without a login. A post whose main media is a video becomes a video;
otherwise the post and the thread above it, walked through `parent`, become one article with a section per
message.

    read(url, web, report) -> Document | Video
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from urllib.parse import urlparse

from package import Document, Report, Video, asset_path
from web import Web

SYNDICATION = "https://cdn.syndication.twimg.com/tweet-result"
_STATUS = re.compile(r"/status(?:es)?/(\d+)")
_ARTICLE = re.compile(r"/i/article/(\d+)")
THREAD_LIMIT = 25


def read(url: str, web: Web, report: Report) -> Document | Video:
    report("fetchingPage", None, None)
    path = urlparse(url).path
    if _ARTICLE.search(path):
        raise ValueError("X article text is not in a public fetch; oEmbed only returns a short post")
    match = _STATUS.search(path)
    if match is None:
        raise ValueError("X link is not a single post")
    post = _tweet(web, match.group(1))
    article = _article_link(post)
    if article is not None:
        raise ValueError(f"the post carries an X article ({article}); its text needs a logged-in fetch the server does not make yet")
    if _main_video(post) is not None:
        return _video(post, url)
    return _document(web, post, report)


def _article_link(post: dict) -> str | None:
    """An article card post: its only content is an https://x.com/i/article/… link."""
    for entity in (post.get("entities") or {}).get("urls") or []:
        expanded = entity.get("expanded_url") or ""
        if _ARTICLE.search(urlparse(expanded).path):
            remainder = _plain(post).replace(expanded, "").replace(entity.get("url") or "", "").strip(" 🧵")
            if not remainder:
                return expanded
    return None


def _tweet(web: Web, status_id: str) -> dict:
    payload = json.loads(web.text(f"{SYNDICATION}?id={status_id}&token=a&lang=en"))
    if payload.get("__typename") != "Tweet":
        raise ValueError("X did not return the post")
    return payload


def _main_video(post: dict) -> dict | None:
    for item in post.get("mediaDetails") or []:
        if item.get("type") in ("video", "animated_gif"):
            return item
    return None


def _video(post: dict, url: str) -> Video:
    user = post.get("user") or {}
    title = _first_words(post.get("text") or "") or (user.get("name") or "X")
    return Video(f"x-{post['id_str']}", title, (user.get("name") or "").strip() or None, page=url)


def _document(web: Web, post: dict, report: Report) -> Document:
    files: dict[str, bytes] = {}
    sections = []
    for message in _thread(post):
        name = ((message.get("user") or {}).get("name") or "X").strip()
        sections.append(f"## {name} · {_date(message.get('created_at'))}\n\n{_message_text(message, web, files, report)}")
    quoted = post.get("quoted_tweet")
    if quoted:
        name = ((quoted.get("user") or {}).get("name") or "X").strip()
        sections.append(f"## Quoted: {name}\n\n> {_plain(quoted)}")
    author = ((post.get("user") or {}).get("name") or "").strip() or None
    title = author or "X"
    return Document("# " + title + "\n\n" + "\n\n".join(sections) + "\n", title, author, files=files)


def _thread(post: dict) -> list[dict]:
    """The linked post and the messages above it, root first; `parent` rides inside each payload."""
    messages = [post]
    current = post
    while len(messages) < THREAD_LIMIT:
        parent = current.get("parent")
        if not isinstance(parent, dict) or not parent.get("id_str"):
            break
        messages.insert(0, parent)
        current = parent
    return messages


def _message_text(post: dict, web: Web, files: dict[str, bytes], report: Report) -> str:
    parts = [_plain(post)]
    index = 0
    for item in post.get("mediaDetails") or []:
        if item.get("type") != "photo":
            continue
        source = item.get("media_url_https")
        if not source:
            continue
        path = asset_path(source, f"-{index}.jpg")
        index += 1
        if path not in files:
            report("fetchingAssets", len(files), None)
            files[path] = web.bytes(f"{source}?name=large")
        parts.append(f"![{index}]({path})")
    return "\n\n".join(part for part in parts if part)


def _plain(post: dict) -> str:
    text = post.get("text") or ""
    for entity in (post.get("entities") or {}).get("urls") or []:
        text = text.replace(entity.get("url") or "", entity.get("expanded_url") or entity.get("url") or "")
    return text.strip()


def _first_words(text: str, count: int = 8) -> str:
    words = text.split()
    return " ".join(words[:count]) + ("…" if len(words) > count else "")


def _date(value: str | None) -> str:
    if not value:
        return "undated"
    return datetime.fromisoformat(value.replace("Z", "+00:00")).strftime("%-d %b %Y")

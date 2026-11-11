"""X posts, threads and articles.

Every read starts with the public syndication payload: the post's text, author, photos, video, quoted
post and the messages above it. What the public payload cannot give — the author's continuation of a
thread and a long-form article's body — is read in the reader browser, the hidden Chrome on the
logged-in profile, and parsed from the page it renders. Without the reader a thread still imports as
the post and the messages above it, and an article refuses with its reason.

    read(url, web, report) -> Document
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from urllib.parse import urlparse

from lxml import html

from package import Document, Report, asset_path
import reader
from web import Web

SYNDICATION = "https://cdn.syndication.twimg.com/tweet-result"
HOME = "https://x.com"
_STATUS = re.compile(r"/status(?:es)?/(\d+)")
_ARTICLE = re.compile(r"/i/article/(\d+)")
_TRAILING_LINK = re.compile(r"(?:\s*https://t\.co/\w+)+\s*$")
THREAD_LIMIT = 25


def read(url: str, web: Web, report: Report) -> Document:
    report("fetchingPage", None, None)
    path = urlparse(url).path
    if _ARTICLE.search(path):
        return _article(url, report)
    match = _STATUS.search(path)
    if match is None:
        raise ValueError("X link is not a single post")
    post = _tweet(web, match.group(1))
    article = _article_link(post)
    if article is not None:
        return _article(article, report)
    return _thread(post, url, web, report)


def _tweet(web: Web, status_id: str) -> dict:
    payload = json.loads(web.text(f"{SYNDICATION}?id={status_id}&token=a&lang=en"))
    if payload.get("__typename") != "Tweet":
        raise ValueError("X did not return the post")
    return payload


def _article_link(post: dict) -> str | None:
    """A post that is only an article card: its whole content is an https://x.com/i/article/… link."""
    for entity in (post.get("entities") or {}).get("urls") or []:
        expanded = entity.get("expanded_url") or ""
        if _ARTICLE.search(urlparse(expanded).path):
            remainder = _plain(post).replace(expanded, "").replace(entity.get("url") or "", "").strip(" 🧵")
            if not remainder:
                return expanded
    return None


def _stream(item: dict) -> str | None:
    """The playable address the syndication payload carries: adaptive HLS first, then the largest mp4."""
    variants = ((item.get("video_info") or {}).get("variants")) or []
    hls = next((v.get("url") for v in variants if v.get("content_type") == "application/x-mpegURL" and v.get("url")), None)
    if hls:
        return hls
    mp4s = [v for v in variants if v.get("content_type") == "video/mp4" and v.get("url")]
    return max(mp4s, key=lambda v: v.get("bitrate") or 0).get("url") if mp4s else None


def _article(url: str, report: Report) -> Document:
    """A long-form article renders only for the logged-in reader; its body is the article view's draft blocks."""
    try:
        with reader.job("x") as tab:
            markup = tab.render(url)
            title, author, paragraphs, images = _article_parts(markup)
            files: dict[str, bytes] = {}
            lines = list(paragraphs)
            for index, source in enumerate(images):
                report("fetchingAssets", index + 1, len(images))
                path = asset_path(source, f"-{index}.jpg")
                files[path] = tab.fetch(source)
                lines.append(f"![{index + 1}]({path})")
    except (reader.ReaderError, OSError) as error:
        raise ValueError(f"the article needs the reader browser: {error}") from error
    return Document("# " + title + "\n\n" + "\n\n".join(lines) + "\n", title, author, files=files)


def _article_parts(markup: str) -> tuple[str, str | None, list[str], list[str]]:
    document = html.fromstring(markup)
    views = document.xpath('//div[@data-testid="twitterArticleRichTextView"]')
    if not views:
        raise ValueError("the article did not render; is the x profile logged in?")
    view = views[0]
    header = [child for child in view.getparent() if child is not view]
    title = header[0].text_content().strip() if header else "X article"
    byline = header[1].text_content().strip() if len(header) > 1 else ""
    author = byline.split("@")[0].strip(" ·") or None
    blocks = view.xpath('.//div[contains(@class,"public-DraftStyleDefault-block")]')
    paragraphs = [block.text_content().strip() for block in blocks]
    images = [src for src in view.xpath('.//img[contains(@src,"/media/")]/@src')]
    return title, author, [p for p in paragraphs if p], images


def _thread(post: dict, url: str, web: Web, report: Report) -> Document:
    """The post and the messages above it come from the syndication payload; the author's continuation
    below it, when the reader browser is there, from the conversation the permalink page renders."""
    files: dict[str, bytes] = {}
    user = post.get("user") or {}
    handle = (user.get("screen_name") or "").strip()
    name = (user.get("name") or "").strip() or "X"
    sections: list[str] = []
    for ancestor in _ancestors(web, post):
        who = ((ancestor.get("user") or {}).get("name") or "X").strip()
        sections.append(f"## {who} · {_date(ancestor.get('created_at'))}\n\n{_plain(ancestor)}")
    sections.append(f"## {name} · {_date(post.get('created_at'))}\n\n{_message_markdown(post, web, files, report)}")
    quoted = post.get("quoted_tweet")
    if quoted:
        who = ((quoted.get("user") or {}).get("name") or "X").strip()
        sections.append(f"## Quoted: {who}\n\n> {_plain(quoted)}")
    try:
        with reader.job("x") as tab:
            tab.goto(_permalink(post))
            tab.crawl(4)
            continuation, media = _continuations(tab.html(), handle, post["id_str"], tab.fetch)
            sections += continuation
            files.update(media)
    except (reader.ReaderError, OSError):
        pass
    return Document("# " + name + "\n\n" + "\n\n".join(sections) + "\n", name, (user.get("name") or "").strip() or None, files=files)


def _ancestors(web: Web, post: dict) -> list[dict]:
    """The messages above the post, root first; `parent` rides inside each syndication payload."""
    messages = []
    current = post
    while len(messages) < THREAD_LIMIT:
        parent = current.get("parent")
        if not isinstance(parent, dict) or not parent.get("id_str"):
            break
        messages.insert(0, parent)
        current = parent
    return messages


def _continuations(markup: str, handle: str, focal_id: str, fetch) -> tuple[list[str], dict[str, bytes]]:
    """The author's own messages in the conversation, the thread going on below the linked post."""
    sections: list[str] = []
    files: dict[str, bytes] = {}
    if not handle:
        return sections, files
    for message in _conversation(markup):
        if message["handle"].lower() != handle.lower() or message["id"] == focal_id or not message["text"]:
            continue
        parts = [message["text"]]
        for index, source in enumerate(message["images"][:4]):
            path = asset_path(source, f"-{index}.jpg")
            if path not in files:
                files[path] = fetch(source)
            parts.append(f"![{index + 1}]({path})")
        sections.append(f"## {message['name']} · {_date(message['posted_at'])}\n\n" + "\n\n".join(parts))
        if len(sections) >= THREAD_LIMIT:
            break
    return sections, files


def _conversation(markup: str) -> list[dict]:
    """Every tweet the page renders, in the order it shows them."""
    document = html.fromstring(markup)
    messages = []
    for article in document.xpath('//article[@data-testid="tweet"]'):
        hrefs = [h for h in article.xpath('.//a[contains(@href,"/status/")]/@href') if "/analytics" not in h]
        match = re.search(r"/([A-Za-z0-9_]+)/status(?:es)?/(\d+)", hrefs[0]) if hrefs else None
        if match is None:
            continue
        texts = article.xpath('.//div[@data-testid="tweetText"]')
        names = article.xpath('.//div[@data-testid="User-Name"]//text()')
        times = article.xpath('.//time/@datetime')
        messages.append({
            "handle": match.group(1),
            "id": match.group(2),
            "name": next((n.strip() for n in names if n.strip()), match.group(1)),
            "text": texts[0].text_content().strip() if texts else None,
            "posted_at": times[0] if times else None,
            "images": [src for src in article.xpath('.//img[contains(@src,"/media/")]/@src')],
        })
    return messages


def _message_markdown(post: dict, web: Web, files: dict[str, bytes], report: Report) -> str:
    parts = [_plain(post)]
    index = 0
    for item in post.get("mediaDetails") or []:
        if item.get("type") == "photo":
            source = item.get("media_url_https")
            if not source:
                continue
            path = asset_path(source, f"-{index}.jpg")
            index += 1
            if path not in files:
                report("fetchingAssets", len(files), None)
                files[path] = web.bytes(f"{source}?name=large")
            parts.append(f"![{index}]({path})")
        elif item.get("type") in ("video", "animated_gif"):
            poster = item.get("media_url_https")
            if poster:
                path = asset_path(poster, f"-{index}.jpg")
                index += 1
                if path not in files:
                    report("fetchingAssets", len(files), None)
                    files[path] = web.bytes(poster)
                parts.append(f"![{index}]({path})")
            stream = _stream(item) or item.get("expanded_url")
            if stream:
                parts.append(f"[video]({stream})")
    return "\n\n".join(part for part in parts if part)


def _permalink(post: dict) -> str:
    handle = (post.get("user") or {}).get("screen_name") or "x"
    return f"{HOME}/{handle}/status/{post['id_str']}"


def _plain(post: dict) -> str:
    text = post.get("text") or ""
    for entity in (post.get("entities") or {}).get("urls") or []:
        text = text.replace(entity.get("url") or "", entity.get("expanded_url") or entity.get("url") or "")
    return _TRAILING_LINK.sub("", text).strip()


def _first_words(text: str, count: int = 8) -> str:
    words = text.split()
    return " ".join(words[:count]) + ("…" if len(words) > count else "")


def _date(value: str | None) -> str:
    if not value:
        return "undated"
    return datetime.fromisoformat(value.replace("Z", "+00:00")).strftime("%-d %b %Y")

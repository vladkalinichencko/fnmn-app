"""YouTube import package.

Body: each caption cue is one markdown paragraph of plain text, in playback order.
Timed sync for the reader uses blocks with kind "transcript" and startSeconds
(float seconds from the start). The video block uses kind "video" and mediaURL
set to the official embed. An empty body means captions were not available;
the video still plays.
"""

from __future__ import annotations

import hashlib
import html
import re
from urllib.parse import parse_qs, urlparse

_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


def _stable_id(prefix: str, value: str) -> str:
    return f"{prefix}:{hashlib.sha256(value.encode()).hexdigest()[:24]}"


def youtube_package_live(url: str, folders: list[str] | None = None, cookies_from_browser: str | None = None) -> dict:
    video_id = video_id_from_url(url)
    if video_id is None:
        raise ValueError("YouTube address has no video id")
    source_url = f"https://www.youtube.com/watch?v={video_id}"
    info = _ytdlp_info(source_url, download=False, cookies_from_browser=cookies_from_browser)
    title = (info.get("title") or "").strip() or video_id
    author = (info.get("uploader") or info.get("channel") or "").strip() or None
    language = _caption_language(info)
    cues: list[tuple[float, str]] = []
    if language:
        try:
            cues = _download_cues(source_url, language, cookies_from_browser)
        except Exception:
            cues = []
    return _package(video_id, source_url, title, author, cues, folders or [])


def video_id_from_url(url: str) -> str | None:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if host == "youtu.be":
        candidate = parsed.path.strip("/").split("/")[0]
        return candidate if _ID.match(candidate) else None
    if host == "youtube.com" or host.endswith(".youtube.com"):
        query = parse_qs(parsed.query)
        if "v" in query and _ID.match(query["v"][0]):
            return query["v"][0]
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) >= 2 and parts[0] in {"embed", "shorts", "live", "v"} and _ID.match(parts[1]):
            return parts[1]
    return None


def cues_from_timedtext(payload: str) -> list[tuple[float, str]]:
    text = payload.strip()
    if not text.startswith("WEBVTT"):
        return []
    return _cues_from_vtt(text)


def _cues_from_vtt(payload: str) -> list[tuple[float, str]]:
    cues: list[tuple[float, str]] = []
    blocks = re.split(r"\n\n+", payload.strip())
    for block in blocks:
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        if not lines or lines[0] == "WEBVTT":
            continue
        timing = next((line for line in lines if "-->" in line), None)
        if timing is None:
            continue
        start = timing.split("-->", 1)[0].strip()
        text = _clean(" ".join(line for line in lines if line != timing and not line.isdigit()))
        if text:
            cues.append((_vtt_seconds(start), text))
    return cues


def _vtt_seconds(stamp: str) -> float:
    parts = stamp.replace(",", ".").split(":")
    values = [float(part) for part in parts]
    while len(values) < 3:
        values.insert(0, 0.0)
    hours, minutes, seconds = values[-3:]
    return hours * 3600 + minutes * 60 + seconds


def _clean(text: str) -> str:
    plain = re.sub(r"<[^>]+>", "", html.unescape(text))
    return " ".join(plain.replace("\n", " ").split())


def _ytdlp_info(url: str, download: bool, cookies_from_browser: str | None = None) -> dict:
    import yt_dlp

    options = {
        "skip_download": True,
        "noplaylist": True,
        "quiet": True,
        "js_runtimes": {"node": {"path": "node"}},
        **_browser_cookies(cookies_from_browser),
    }
    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(url, download=download)
    if not isinstance(info, dict):
        raise ValueError("yt-dlp returned no video")
    return info


def _caption_language(info: dict) -> str | None:
    manual = info.get("subtitles") or {}
    automatic = info.get("automatic_captions") or {}
    preferred = [info.get("language") or "", "en", "en-US", "en-orig"]
    for code in preferred:
        code = str(code).lower()
        if not code:
            continue
        for tracks in (manual, automatic):
            for key in tracks:
                if key == "live_chat":
                    continue
                if key == code or key.startswith(code + "-"):
                    return key
    for tracks in (manual, automatic):
        for key in tracks:
            if key != "live_chat":
                return key
    return None


def _download_cues(url: str, language: str, cookies_from_browser: str | None = None) -> list[tuple[float, str]]:
    import tempfile
    from pathlib import Path

    with tempfile.TemporaryDirectory() as tmp:
        options_holder = Path(tmp)
        _ytdlp_download(url, language, options_holder, cookies_from_browser)
        files = sorted(options_holder.glob("*.vtt"))
        if not files:
            return []
        return cues_from_timedtext(files[0].read_text(encoding="utf-8"))


def _ytdlp_download(url: str, language: str, directory, cookies_from_browser: str | None = None) -> None:
    import yt_dlp

    options = {
        "skip_download": True,
        "noplaylist": True,
        "quiet": True,
        "writesubtitles": True,
        "writeautomaticsub": True,
        "subtitleslangs": [language],
        "subtitlesformat": "vtt",
        "outtmpl": str(directory / "%(id)s"),
        "js_runtimes": {"node": {"path": "node"}},
        **_browser_cookies(cookies_from_browser),
    }
    with yt_dlp.YoutubeDL(options) as ydl:
        ydl.extract_info(url, download=True)


def _browser_cookies(browser: str | None) -> dict:
    if not browser:
        return {}
    return {"cookiesfrombrowser": (browser,)}


def _package(
    video_id: str,
    source_url: str,
    title: str,
    author: str | None,
    cues: list[tuple[float, str]],
    folders: list[str],
) -> dict:
    material_id = f"youtube:{video_id}"
    section_id = _stable_id("section", f"{material_id}:video")
    video_block_id = _stable_id("block", f"{material_id}:video")
    blocks = [{
        "id": video_block_id,
        "sectionID": section_id,
        "kind": "video",
        "html": title,
        "sourceFragment": None,
        "mediaURL": f"https://www.youtube.com/embed/{video_id}",
        "startSeconds": 0.0,
    }]
    paragraphs = []
    for index, (start, text) in enumerate(cues):
        block_id = _stable_id("block", f"{material_id}:cue:{index}:{start}:{text}")
        blocks.append({
            "id": block_id,
            "sectionID": section_id,
            "kind": "transcript",
            "html": text,
            "sourceFragment": None,
            "mediaURL": None,
            "startSeconds": start,
        })
        paragraphs.append(text)
    body = "\n\n".join(paragraphs)
    return {
        "version": 1,
        "material": {
            "id": material_id,
            "kind": "video",
            "title": title,
            "sourceURL": source_url,
            "byline": author,
        },
        "sections": [{
            "id": section_id,
            "parentID": None,
            "title": title,
            "level": 1,
            "firstBlockID": video_block_id,
        }],
        "blocks": blocks,
        "folders": folders,
        "body": body,
        "files": {},
    }

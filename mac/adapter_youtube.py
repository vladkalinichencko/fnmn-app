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
import json
import re
import xml.etree.ElementTree as ET
from urllib.parse import parse_qs, urlparse

_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


def _stable_id(prefix: str, value: str) -> str:
    return f"{prefix}:{hashlib.sha256(value.encode()).hexdigest()[:24]}"


def youtube_package_live(url: str, folders: list[str] | None = None) -> dict:
    video_id = video_id_from_url(url)
    if video_id is None:
        raise ValueError("YouTube address has no video id")
    source_url = f"https://www.youtube.com/watch?v={video_id}"
    info = _ytdlp_info(source_url, download=False)
    title = (info.get("title") or "").strip() or video_id
    author = (info.get("uploader") or info.get("channel") or "").strip() or None
    language = _caption_language(info)
    cues: list[tuple[float, str]] = []
    note = None
    if language:
        try:
            cues = _download_cues(source_url, language)
        except Exception as error:
            note = f"Captions did not download: {error}"
    if not cues and note is None:
        note = "YouTube did not return caption text."
    if cues:
        note = None
    return _package(video_id, source_url, title, author, cues, note, folders or [])


def youtube_package(url: str, fetch_text, folders: list[str] | None = None) -> dict:
    video_id = video_id_from_url(url)
    if video_id is None:
        raise ValueError("YouTube address has no video id")
    source_url = f"https://www.youtube.com/watch?v={video_id}"
    title, author, tracks = _page_details(video_id, source_url, fetch_text)
    cues, caption_note = _captions_from_tracks(tracks, fetch_text)
    return _package(video_id, source_url, title, author, cues, caption_note, folders or [])


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
    if not text:
        return []
    if text.startswith("{"):
        return _cues_from_json3(json.loads(text))
    if text.startswith("WEBVTT"):
        return _cues_from_vtt(text)
    if text.startswith("<"):
        return _cues_from_xml(text)
    return []


def _page_details(video_id: str, source_url: str, fetch_text) -> tuple[str, str | None, list[dict]]:
    title = video_id
    author = None
    try:
        oembed = json.loads(fetch_text(f"https://www.youtube.com/oembed?url={source_url}&format=json"))
        title = (oembed.get("title") or title).strip() or title
        author = (oembed.get("author_name") or "").strip() or None
    except Exception:
        pass
    page_title, page_author, tracks = _player_page(video_id, fetch_text)
    if page_title:
        title = page_title
    if page_author:
        author = page_author
    return title, author, tracks


def _captions_from_tracks(tracks: list[dict], fetch_text) -> tuple[list[tuple[float, str]], str | None]:
    if not tracks:
        return [], "Captions were not listed for this video."
    track = _preferred_track(tracks)
    base = html.unescape(track.get("baseUrl") or "")
    if not base:
        return [], "Caption track had no timedtext URL."
    for suffix in ("&fmt=json3", "&fmt=srv3", ""):
        try:
            payload = fetch_text(base + suffix)
        except Exception:
            continue
        cues = cues_from_timedtext(payload)
        if cues:
            return cues, None
    return [], "Caption track listed, but timedtext returned no cues."


def _player_page(video_id: str, fetch_text) -> tuple[str | None, str | None, list[dict]]:
    try:
        page = fetch_text(f"https://www.youtube.com/watch?v={video_id}")
    except Exception:
        return None, None, []
    data = _player_response(page)
    if not data:
        return None, None, []
    details = data.get("videoDetails") or {}
    title = (details.get("title") or "").strip() or None
    author = (details.get("author") or "").strip() or None
    tracks = ((data.get("captions") or {}).get("playerCaptionsTracklistRenderer") or {}).get("captionTracks") or []
    return title, author, [track for track in tracks if isinstance(track, dict)]


def _player_response(page: str) -> dict | None:
    start = page.find("ytInitialPlayerResponse")
    if start < 0:
        return None
    brace = page.find("{", page.find("=", start))
    if brace < 0:
        return None
    depth = 0
    for index, char in enumerate(page[brace:], brace):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                try:
                    parsed = json.loads(page[brace : index + 1])
                except json.JSONDecodeError:
                    return None
                return parsed if isinstance(parsed, dict) else None
    return None


def _preferred_track(tracks: list[dict]) -> dict:
    def score(track: dict) -> tuple[int, int, str]:
        lang = (track.get("languageCode") or "").lower()
        asr = 1 if track.get("kind") == "asr" else 0
        english = 0 if lang.startswith("en") else 1
        return (asr, english, lang)

    return sorted(tracks, key=score)[0]


def _cues_from_json3(data: dict) -> list[tuple[float, str]]:
    cues: list[tuple[float, str]] = []
    for event in data.get("events") or []:
        if not isinstance(event, dict):
            continue
        start_ms = event.get("tStartMs")
        if start_ms is None:
            continue
        parts = []
        for segment in event.get("segs") or []:
            if isinstance(segment, dict) and segment.get("utf8"):
                parts.append(segment["utf8"])
        text = _clean("".join(parts))
        if text:
            cues.append((float(start_ms) / 1000.0, text))
    return cues


def _cues_from_xml(payload: str) -> list[tuple[float, str]]:
    try:
        root = ET.fromstring(payload)
    except ET.ParseError:
        return []
    cues: list[tuple[float, str]] = []
    for node in root.iter():
        tag = node.tag.rsplit("}", 1)[-1].lower()
        if tag not in {"text", "p"}:
            continue
        start = node.get("start") or node.get("t")
        if start is None:
            continue
        try:
            seconds = float(start)
            if node.get("t") is not None and "." not in start and seconds > 1000:
                seconds = seconds / 1000.0
        except ValueError:
            continue
        text = _clean("".join(node.itertext()))
        if text:
            cues.append((seconds, text))
    return cues


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


def _ytdlp_info(url: str, download: bool) -> dict:
    import yt_dlp

    options = {
        "skip_download": True,
        "noplaylist": True,
        "quiet": True,
        "js_runtimes": {"node": {"path": "node"}},
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


def _download_cues(url: str, language: str) -> list[tuple[float, str]]:
    import tempfile
    from pathlib import Path

    with tempfile.TemporaryDirectory() as tmp:
        options_holder = Path(tmp)
        _ytdlp_download(url, language, options_holder)
        files = sorted(options_holder.glob("*.vtt"))
        if not files:
            return []
        return cues_from_timedtext(files[0].read_text(encoding="utf-8"))


def _ytdlp_download(url: str, language: str, directory) -> None:
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
    }
    with yt_dlp.YoutubeDL(options) as ydl:
        ydl.extract_info(url, download=True)


def _package(
    video_id: str,
    source_url: str,
    title: str,
    author: str | None,
    cues: list[tuple[float, str]],
    caption_note: str | None,
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
    if caption_note and not cues:
        body = ""
    package = {
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
    if caption_note:
        package["captionNote"] = caption_note
    return package

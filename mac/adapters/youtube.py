"""A YouTube video with its captions as timed transcript cues.

yt-dlp reads the title, the channel and one caption track on the Mac. A video
without any caption track still plays; a caption track that fails to download
stops the import instead of silently leaving the transcript empty.
"""

from __future__ import annotations

import html
import re
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from package import ImportFailure, Report, Video
from web import Web

_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_OPTIONS = {"skip_download": True, "noplaylist": True, "quiet": True, "noprogress": True,
            "js_runtimes": {"node": {"path": "node"}}}


def read(url: str, web: Web, report: Report) -> Video:
    video_id = video_id_from_url(url)
    if video_id is None:
        raise ValueError("YouTube address has no video id")
    watch_url = f"https://www.youtube.com/watch?v={video_id}"
    report("fetchingPage", None, None)
    info = _info(watch_url)
    title = (info.get("title") or "").strip() or video_id
    author = (info.get("uploader") or info.get("channel") or "").strip() or None
    language = _caption_language(info)
    if language is None:
        return Video(video_id, title, author)
    report("fetchingAssets", None, None)
    try:
        cues = _download_cues(watch_url, language)
    except Exception as error:
        raise ImportFailure("fetchingAssets", f"captions: {error}") from error
    return Video(video_id, title, author, cues)


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


def _info(url: str) -> dict:
    import yt_dlp

    with yt_dlp.YoutubeDL(_OPTIONS) as ydl:
        info = ydl.extract_info(url, download=False)
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
    import yt_dlp

    with tempfile.TemporaryDirectory() as directory:
        options = {**_OPTIONS, "writesubtitles": True, "writeautomaticsub": True, "subtitleslangs": [language],
                   "subtitlesformat": "vtt", "outtmpl": str(Path(directory) / "%(id)s")}
        with yt_dlp.YoutubeDL(options) as ydl:
            ydl.extract_info(url, download=True)
        files = sorted(Path(directory).glob("*.vtt"))
        return cues_from_timedtext(files[0].read_text(encoding="utf-8")) if files else []

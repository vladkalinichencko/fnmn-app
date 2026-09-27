"""Export every video in a YouTube playlist library to CSV.

One row per (playlist, video) with adjacent fields for clustering:

    playlist, playlist_url, video_title, channel, video_url

Default source is the account library tab (saved + created playlists,
Watch Later, Liked), which needs login cookies:

    python3 mac/playlist_export.py --cookies cookies.txt -o playlists.csv

Pass --playlist (repeatable) to export specific playlists instead.
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
import sys
from pathlib import Path

LIBRARY = "https://www.youtube.com/feed/playlists"

# The two pseudo-playlists do not resolve as playlist?list= IDs.
SPECIAL = {"WL": ":ytwatchlater", "LL": ":ytliked"}


def playlist_source(playlist_id: str) -> str:
    if playlist_id in SPECIAL:
        return SPECIAL[playlist_id]
    return f"https://www.youtube.com/playlist?list={playlist_id}"


def dump_json_lines(command: list[str]) -> list[dict]:
    if shutil.which("yt-dlp") is None:
        raise RuntimeError("yt-dlp not found on PATH (pip install -r mac/requirements.txt)")
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert process.stdout is not None
    entries: list[dict] = []
    for line in process.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    _, stderr = process.communicate()
    if process.returncode != 0:
        raise RuntimeError((stderr.strip().splitlines() or ["yt-dlp failed"])[-1])
    return entries


def auth_flags(cookies_from_browser: str | None, cookies_file: str | None) -> list[str]:
    flags: list[str] = []
    if cookies_from_browser:
        flags += ["--cookies-from-browser", cookies_from_browser]
    if cookies_file:
        flags += ["--cookies", cookies_file]
    return flags


def list_library(cookies_from_browser: str | None, cookies_file: str | None) -> list[dict]:
    command = ["yt-dlp", "--flat-playlist", "--skip-download", "--dump-json", "--no-warnings"]
    command += auth_flags(cookies_from_browser, cookies_file)
    command.append(LIBRARY)
    playlists = []
    for entry in dump_json_lines(command):
        playlist_id = entry.get("id")
        if not isinstance(playlist_id, str) or not playlist_id:
            continue
        playlists.append({"id": playlist_id, "title": entry.get("title") or playlist_id})
    return playlists


def videos_in_playlist(playlist: dict, cookies_from_browser: str | None, cookies_file: str | None) -> list[dict]:
    command = ["yt-dlp", "--flat-playlist", "--skip-download", "--dump-json", "--no-warnings"]
    command += auth_flags(cookies_from_browser, cookies_file)
    command.append(playlist_source(playlist["id"]))
    rows = []
    for entry in dump_json_lines(command):
        video_id = entry.get("id")
        if not isinstance(video_id, str) or not video_id:
            continue
        rows.append({
            "playlist": playlist["title"],
            "playlist_url": f"https://www.youtube.com/playlist?list={playlist['id']}",
            "video_title": entry.get("title") or "",
            "channel": entry.get("channel") or entry.get("uploader") or "",
            "video_url": f"https://www.youtube.com/watch?v={video_id}",
        })
    return rows


FIELDS = ["playlist", "playlist_url", "video_title", "channel", "video_url", "status"]


def enrich_missing(rows: list[dict], cookies_from_browser: str | None = None, cookies_file: str | None = None) -> int:
    """Fill blank channel/title cells via YouTube oEmbed (lightweight, no login).

    The HTTP status itself classifies each video: 200 fills title + channel
    and marks it ok; 401/403/404 marks it unavailable (private, removed or
    terminated account); anything inconclusive stays unknown.
    """
    import time
    import urllib.error
    import urllib.request
    from concurrent.futures import ThreadPoolExecutor

    for row in rows:
        row.setdefault("status", "ok" if (row.get("video_title") and row.get("channel")) else "")

    targets = [row for row in rows if not row["channel"] or not row["video_title"]]
    if not targets:
        return 0
    print(f"enriching {len(targets)} videos via oEmbed…", file=sys.stderr)

    def fetch(row: dict) -> str:
        url = "https://www.youtube.com/oembed?url=" + row["video_url"] + "&format=json"
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=15) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                if not row["video_title"]:
                    row["video_title"] = payload.get("title") or ""
                if not row["channel"]:
                    row["channel"] = payload.get("author_name") or ""
                return "ok"
            except urllib.error.HTTPError as error:
                if error.code == 429:
                    time.sleep(10 * (attempt + 1))
                    continue
                if error.code in (401, 403, 404):
                    return "unavailable"
                return "unknown"
            except Exception:
                return "unknown"
        return "unknown"

    with ThreadPoolExecutor(max_workers=6) as pool:
        statuses = list(pool.map(fetch, targets))
    filled = 0
    for row, status in zip(targets, statuses):
        row["status"] = status
        if status == "ok":
            filled += 1
    return filled


def export_playlists(playlists: list[dict], output: Path, cookies_from_browser: str | None, cookies_file: str | None, enrich: bool) -> None:
    skipped: list[str] = []
    rows: list[dict] = []
    for index, playlist in enumerate(playlists, 1):
        try:
            found = videos_in_playlist(playlist, cookies_from_browser, cookies_file)
        except RuntimeError as error:
            skipped.append(f"{playlist['title']} ({error})")
            print(f"[{index}/{len(playlists)}] SKIP {playlist['title']}: {error}", file=sys.stderr)
            continue
        rows += found
        print(f"[{index}/{len(playlists)}] {playlist['title']}: {len(found)} videos", file=sys.stderr)
    # Feed tabs (Watch Later) omit channel/title on some entries; backfill
    # from rows where the same video appeared with full metadata.
    known: dict[str, dict] = {}
    for row in rows:
        if row["video_title"] or row["channel"]:
            known.setdefault(row["video_url"], row)
    filled = 0
    for row in rows:
        source = known.get(row["video_url"])
        if not source:
            continue
        for field in ("video_title", "channel"):
            if not row[field] and source[field]:
                row[field] = source[field]
                filled += 1
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    enriched = enrich_missing(rows) if enrich else 0
    if enriched:
        with output.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
    print(f"wrote {len(rows)} rows to {output} (backfilled {filled} fields, enriched {enriched})", file=sys.stderr)
    for name in skipped:
        print(f"skipped: {name}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description="Export playlist videos to CSV: playlist, url, title, channel, video url.")
    parser.add_argument("-o", "--output", type=Path, default=Path("playlists.csv"))
    parser.add_argument("--cookies-from-browser", default=None, help="e.g. chrome, safari, firefox")
    parser.add_argument("--cookies", default=None, help="Netscape cookies.txt from a logged-in browser")
    parser.add_argument("--playlist", action="append", default=[], help="playlist URL or ID to export (repeatable; default: whole library)")
    parser.add_argument("--enrich", action="store_true", help="fetch channel/title for rows missing them (slower, parallel)")
    args = parser.parse_args()

    if args.playlist:
        playlists = [{"id": value.split("list=")[-1] if "list=" in value else value, "title": value} for value in args.playlist]
        # Resolve display titles through the library listing when possible.
        try:
            known = {item["id"]: item["title"] for item in list_library(args.cookies_from_browser, args.cookies)}
        except RuntimeError:
            known = {}
        for item in playlists:
            item["title"] = known.get(item["id"], item["title"])
    else:
        playlists = list_library(args.cookies_from_browser, args.cookies)
    if not playlists:
        raise RuntimeError("no playlists found; check login cookies")
    export_playlists(playlists, args.output, args.cookies_from_browser, args.cookies, args.enrich)


if __name__ == "__main__":
    main()

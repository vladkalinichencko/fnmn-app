"""Build the catalog input and album table for a bulk YouTube playlist import.

    cd server && ../.venv/bin/python -m collect.youtube_library \
        ../playlists.csv ../watchlater.txt \
        --playlist "Туториалы" --watch-later \
        --catalog "$HOME/Library/Mobile Documents/com~apple~CloudDocs/REED/catalog.json" \
        --output /tmp/yt-library.json --albums collect/youtube_albums.tsv

Reads the playlist export (playlist, playlist_url, video_title, channel, video_url) and the
Watch Later URL list, keeps only videos not already in the catalog, canonicalizes every
address to youtube.com/watch?v=<id> so a video in two playlists or under two URL forms is
one material, and emits what prepare_browser_library needs: a catalog.json with the new
videos grouped under their playlist sources, and an albums table with album = channel.
Rerunning after a partial import adds only what is missing. Videos stream in the app;
only title, channel and the caption track are fetched.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

from adapters.youtube import video_id_from_url
from collect.prepare_browser_library import ALBUMS as DEFAULT_ALBUMS

WATCH_LATER = "Watch later"
WATCH_LATER_URL = "https://www.youtube.com/playlist?list=WL"


def _canonical(url: str) -> str:
    video_id = video_id_from_url(url)
    return f"https://www.youtube.com/watch?v={video_id}" if video_id else url


def _clean(value: str) -> str:
    return re.sub(r"[\t\n\r]+", " ", value).strip()


def _catalog_video_ids(catalog: dict) -> set[str]:
    return {video_id for source in catalog["sources"] for material in source["materials"]
            if (video_id := video_id_from_url(material["url"]))}


def _csv_rows(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def build(args: argparse.Namespace) -> tuple[dict, list[list[str]], dict[str, int], int]:
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    known = _catalog_video_ids(catalog)
    wanted = set(args.playlist or []) | ({WATCH_LATER} if args.watch_later else set())
    stats = {"rows": 0, "skipped_known": 0, "skipped_bad": 0}

    videos: dict[str, dict] = {}
    members: dict[str, list[str]] = {}
    playlist_urls: dict[str, str] = {}
    for row in _csv_rows(args.playlists_csv):
        stats["rows"] += 1
        playlist = _clean(row.get("playlist") or "")
        if playlist not in wanted:
            continue
        url = _canonical((row.get("video_url") or "").strip())
        video_id = video_id_from_url(url)
        if video_id is None:
            stats["skipped_bad"] += 1
            continue
        if video_id in known:
            stats["skipped_known"] += 1
            continue
        if url not in videos:
            videos[url] = {"title": _clean(row.get("video_title") or "") or video_id,
                           "channel": _clean(row.get("channel") or "")}
        bucket = members.setdefault(playlist, [])
        if url not in bucket:
            bucket.append(url)
        playlist_urls.setdefault(playlist, (row.get("playlist_url") or "").strip())

    if args.watch_later:
        seen = {video_id_from_url(url) for url in videos}
        for raw in args.watchlater_text.splitlines():
            url = _canonical(raw.strip())
            video_id = video_id_from_url(url)
            if video_id is None:
                stats["skipped_bad"] += 1
            elif video_id in known or video_id in seen:
                stats["skipped_known"] += 1
            else:
                videos[url] = {"title": video_id, "channel": ""}
                seen.add(video_id)
                members.setdefault(WATCH_LATER, []).append(url)
        if members.get(WATCH_LATER):
            playlist_urls.setdefault(WATCH_LATER, WATCH_LATER_URL)

    new_materials = 0
    for playlist in members:
        materials = [{"title": videos[url]["title"], "url": url, "saved_in": [], "found_in": []}
                     for url in members[playlist]]
        catalog["sources"].append({"name": playlist, "url": playlist_urls[playlist],
                                   "kind": "youtube_playlist", "saved_in": [], "found_in": [],
                                   "materials": materials})
        new_materials += len(materials)

    albums = [line.split("\t") for line in args.albums_source_text.splitlines()[1:] if line.strip()]
    have = {row[4] for row in albums if len(row) == 5}
    for url, video in videos.items():
        if url in have:
            continue
        channel = video["channel"] or "Watch Later"
        albums.append([_clean(channel) or "Watch Later", "", "YouTube", video["title"], url])
    return catalog, albums, stats, new_materials


def main() -> None:
    parser = argparse.ArgumentParser(description="Build catalog input and channel albums for YouTube playlists")
    parser.add_argument("playlists_csv", type=Path)
    parser.add_argument("watchlater", type=Path, nargs="?", default=None)
    parser.add_argument("--playlist", action="append", help="Playlist name to include; repeatable")
    parser.add_argument("--watch-later", action="store_true", help="Include the Watch later playlist and URL list")
    parser.add_argument("--catalog", type=Path, required=True, help="Current catalog.json to extend")
    parser.add_argument("--output", type=Path, required=True, help="Merged catalog.json for prepare_browser_library")
    parser.add_argument("--albums", type=Path, required=True, help="Albums table to write for --albums of prepare_browser_library")
    parser.add_argument("--albums-source", type=Path, default=DEFAULT_ALBUMS,
                        help="Reviewed albums table to keep; defaults to browser_albums.tsv")
    args = parser.parse_args()

    args.watchlater_text = args.watchlater.read_text(encoding="utf-8") if args.watchlater else ""
    args.albums_source_text = args.albums_source.read_text(encoding="utf-8")
    catalog, albums, stats, new_materials = build(args)

    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    header = args.albums_source_text.splitlines()[0].split("\t")
    args.albums.write_text("\n".join(["\t".join(header)] + ["\t".join(row) for row in albums]) + "\n",
                           encoding="utf-8")
    print(f"{new_materials} new materials ({stats['skipped_known']} already known, "
          f"{stats['skipped_bad']} unparseable of {stats['rows']} csv rows); {len(albums)} album rows")


if __name__ == "__main__":
    main()

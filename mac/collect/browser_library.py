"""Build a source-centered library from Safari and selected Dia folders.

    python3 mac/browser_library.py -o browser-library.json

The output keeps each source once, records every collection where a saved URL
appeared, and expands saved YouTube playlists into their videos.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen

from collect.browser_links_export import dia_bookmarks, safari_reading_list, safari_tab_groups


DIA_FOLDERS = {
    ("Study", "Bookmarks Bar/Study/Theory Sources"): "dia-study-theory-sources",
    ("Study", "Bookmarks Bar/Study/Theory Videos"): "dia-study-theory-videos",
    ("Personal", "Bookmarks Bar/Personal/UX/UI"): "dia-personal-ux-ui",
}

COLLECTIONS = {
    "safari-reading-list": "Safari Reading List",
    "dia-study-theory-sources": "Theory Sources",
    "dia-study-theory-videos": "Theory Videos",
    "dia-personal-ux-ui": "UX/UI",
}

SAFARI_TAB_GROUPS = {
    "best render engines learning content": "split",
    "Self-studу": "split",
    "research blog posts": "dia-study-theory-sources",
    "UI History": "dia-personal-ux-ui",
}

TRACKING_QUERY_KEYS = {"fbclid", "gclid", "s", "si", "source", "utm_campaign", "utm_content",
                       "utm_medium", "utm_source", "utm_term"}


def canonical_url(url: str) -> str:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower().removeprefix("www.")
    query = parse_qs(parsed.query, keep_blank_values=True)
    query = {key: values for key, values in query.items() if key.lower() not in TRACKING_QUERY_KEYS}
    if host in {"youtube.com", "m.youtube.com", "youtu.be"}:
        if host == "youtu.be":
            video_id = parsed.path.strip("/")
            return f"https://youtube.com/watch?v={video_id}"
        if parsed.path == "/watch":
            keep = {key: query[key] for key in ("v", "list") if key in query}
            query = keep
        host = "youtube.com"
    path = parsed.path or "/"
    if path != "/":
        path = path.rstrip("/")
    return urlunparse((parsed.scheme.lower() or "https", host, path, "", urlencode(query, doseq=True), ""))


def source_for(url: str) -> tuple[str, str]:
    parsed = urlparse(canonical_url(url))
    host, parts = parsed.hostname or "", [part for part in parsed.path.split("/") if part]
    query = parse_qs(parsed.query)

    if host == "youtube.com" and parsed.path == "/playlist" and query.get("list"):
        return canonical_url(url), "youtube_playlist"
    if host == "youtube.com" and parsed.path == "/watch" and query.get("list") not in (None, ["WL"]):
        return f"https://youtube.com/playlist?list={query['list'][0]}", "youtube_playlist"
    if host == "youtube.com" and parsed.path == "/watch":
        return "https://youtube.com", "youtube_channel"
    if host == "youtube.com" and parts and parts[0].startswith("@"):
        return f"https://youtube.com/{parts[0]}", "youtube_channel"
    if host == "x.com" and parts:
        return f"https://x.com/{parts[0]}", "author"
    if host == "github.com" and len(parts) >= 2:
        return f"https://github.com/{parts[0]}/{parts[1]}", "repository"
    if host == "habr.com" and len(parts) >= 3 and parts[1] == "companies":
        return f"https://habr.com/{parts[0]}/companies/{parts[2]}/articles", "publisher"
    if host == "habr.com":
        return "https://habr.com/ru/articles", "publisher"
    if host.endswith(".medium.com"):
        return f"https://{host}", "author"
    if host == "medium.com" and parts and parts[0].startswith("@"):
        return f"https://medium.com/{parts[0]}", "author"
    if host.endswith(".substack.com"):
        return f"https://{host}", "author"
    if host == "ocw.mit.edu" and len(parts) >= 2 and parts[0] == "courses":
        return f"https://ocw.mit.edu/courses/{parts[1]}", "course"
    if host == "publish.obsidian.md" and parts:
        return f"https://publish.obsidian.md/{parts[0]}", "publication"
    return urlunparse((parsed.scheme, host, "/", "", "", "")), "site"


def source_name(url: str, kind: str, saved_title: str) -> str:
    parsed = urlparse(url)
    parts = [part for part in parsed.path.split("/") if part]
    if kind == "youtube_playlist":
        return saved_title
    if parsed.hostname == "x.com" and parts:
        return f"X · @{parts[0]}"
    if parsed.hostname == "github.com" and len(parts) >= 2:
        return f"GitHub · {parts[0]}/{parts[1]}"
    if parsed.hostname == "habr.com" and "companies" in parts:
        return f"Habr · {parts[parts.index('companies') + 1]}"
    if parsed.hostname == "habr.com":
        return "Habr"
    if kind in {"author", "course", "publication", "repository"} and parts:
        return f"{parsed.hostname} · {parts[-1]}"
    return (parsed.hostname or url).removeprefix("www.")


def selected_links(home: Path) -> list[dict]:
    rows = []
    safari = home / "Library/Safari/Bookmarks.plist"
    for row in safari_reading_list(safari):
        rows.append({**row, "collection": "safari-reading-list", "origin": "safari-reading-list"})
    dia = home / "Library/Application Support/Dia/User Data"
    for row in dia_bookmarks(dia):
        if collection := DIA_FOLDERS.get((row["profile"], row["folder"])):
            rows.append({**row, "collection": collection, "origin": collection})
    safari_tabs = home / "Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"
    for row in safari_tab_groups(safari_tabs, set(SAFARI_TAB_GROUPS)):
        collection = SAFARI_TAB_GROUPS[row["folder"]]
        if collection == "split":
            collection = ("dia-study-theory-videos" if urlparse(row["url"]).hostname in {
                "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
            } else "dia-study-theory-sources")
        rows.append({**row, "collection": collection, "origin": f"safari-tab-group:{row['folder']}"})
    return rows


def youtube_playlist(url: str) -> dict:
    command = ["yt-dlp", "--flat-playlist", "--skip-download", "--dump-single-json", "--no-warnings", url]
    process = subprocess.run(command, capture_output=True, text=True)
    if process.returncode:
        raise RuntimeError((process.stderr.strip().splitlines() or ["yt-dlp failed"])[-1])
    return json.loads(process.stdout)


def youtube_channel(url: str) -> tuple[str, str]:
    command = [
        "yt-dlp", "--skip-download", "--no-warnings",
        "--print", "%(.{channel,uploader,channel_url,uploader_url})#j", url,
    ]
    process = subprocess.run(command, capture_output=True, text=True)
    if process.returncode:
        raise RuntimeError((process.stderr.strip().splitlines() or ["yt-dlp failed"])[-1])
    metadata = json.loads(process.stdout)
    channel_url = metadata.get("uploader_url") or metadata.get("channel_url")
    if not channel_url:
        raise RuntimeError("YouTube returned no channel URL")
    name = metadata.get("uploader") or metadata.get("channel") or channel_url
    return canonical_url(channel_url), name


def habr_author(url: str) -> tuple[str, str]:
    request = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urlopen(request, timeout=20) as response:
        html = response.read().decode("utf-8", errors="ignore")
    match = re.search(r'/users/([^/"?]+)/', html)
    if not match:
        raise RuntimeError("Habr returned no author profile")
    username = match.group(1)
    return f"https://habr.com/ru/users/{username}/publications/articles", f"Habr · @{username}"


def build_library(rows: list[dict], overrides: dict | None = None) -> dict:
    overrides = overrides or {}
    sources: dict[str, dict] = {}
    saved_urls: dict[str, dict] = {}
    for row in rows:
        original_url = canonical_url(row["url"])
        override = overrides.get(original_url, {})
        url = canonical_url(override.get("material_url", original_url))
        saved = saved_urls.setdefault(url, {
            "title": row["title"], "url": url, "saved_urls": [], "saved_in": [], "found_in": [],
        })
        if original_url not in saved["saved_urls"]:
            saved["saved_urls"].append(original_url)
        if row["collection"] not in saved["saved_in"]:
            saved["saved_in"].append(row["collection"])
        origin = row.get("origin", row["collection"])
        if origin not in saved["found_in"]:
            saved["found_in"].append(origin)

    review = []
    for saved in saved_urls.values():
        override = next((overrides[url] for url in saved["saved_urls"] if url in overrides), {})
        source_url, kind = source_for(saved["url"])
        source_url = override.get("source_url", source_url)
        kind = override.get("kind", kind)
        source_title = override.get("source_name")
        if not override and kind == "site":
            review.append({"url": saved["url"], "reason": "source catalog is not verified"})
        try:
            parsed = urlparse(saved["url"])
            if not override and kind == "youtube_channel":
                source_url, source_title = youtube_channel(saved["url"])
            elif not override and parsed.hostname == "habr.com" and "/articles/" in parsed.path and "/companies/" not in parsed.path:
                source_url, source_title = habr_author(saved["url"])
                kind = "author"
        except Exception as error:
            review.append({"url": saved["url"], "reason": str(error)})
        source_url = canonical_url(source_url)
        source = sources.setdefault(source_url, {
            "name": source_title or (saved["title"] if source_url == saved["url"] else source_name(source_url, kind, saved["title"])),
            "url": source_url,
            "kind": kind,
            "saved_in": [],
            "found_in": [],
            "materials": [],
        })
        source["saved_in"] = sorted(set(source["saved_in"] + saved["saved_in"]))
        source["found_in"] = sorted(set(source["found_in"] + saved["found_in"]))
        if source_url != saved["url"]:
            source["materials"].append(saved)

    errors = []
    for source in sources.values():
        if source["kind"] != "youtube_playlist":
            continue
        try:
            playlist = youtube_playlist(source["url"])
        except RuntimeError as error:
            errors.append({"url": source["url"], "error": str(error)})
            continue
        source["name"] = playlist.get("title") or source["name"]
        source["materials"] = [{
            "title": entry.get("title") or entry.get("id") or "",
            "url": canonical_url(entry.get("url") or f"https://youtube.com/watch?v={entry['id']}"),
            "saved_in": source["saved_in"],
            "found_in": source["found_in"],
        } for entry in playlist.get("entries", []) if entry.get("id")]

    return {
        "collections": [{"id": key, "name": value} for key, value in COLLECTIONS.items()],
        "sources": sorted(sources.values(), key=lambda source: (source["name"].casefold(), source["url"])),
        "errors": errors,
        "review": review,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", type=Path, default=Path("browser-library.json"))
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--overrides", type=Path, default=Path(__file__).with_name("browser_source_overrides.json"))
    args = parser.parse_args()
    overrides = json.loads(args.overrides.read_text()) if args.overrides.exists() else {}
    library = build_library(selected_links(args.home), overrides)
    args.output.write_text(json.dumps(library, ensure_ascii=False, indent=2) + "\n")
    materials = sum(len(source["materials"]) for source in library["sources"])
    print(f"wrote {len(library['sources'])} sources and {materials} materials to {args.output}")
    if library["errors"]:
        print(f"warning: {len(library['errors'])} sources could not be expanded")
    if library["review"]:
        print(f"warning: {len(library['review'])} saved links need review")


if __name__ == "__main__":
    main()

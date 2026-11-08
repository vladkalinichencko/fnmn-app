"""Prepare the materials in browser-library.json as FNMN deliveries: the one-time start of the library,
kept here with the rest of the collection, away from the service the app talks to.

    cd mac && ../.venv/bin/python -m collect.prepare_browser_library ../browser-library.json \
        ~/Library/Mobile\\ Documents/com~apple~CloudDocs/FNMN

The output is the FNMN folder in iCloud Drive itself, where the phone reads the library: `catalog.json`,
`index.json` (every material with its reviewed albums) and `deliveries/`. Only files that changed are
written, so iCloud uploads only those. The command resumes from completed deliveries. Failed URLs remain in errors.json. Albums come from
browser_albums.tsv beside this file; `--repackage` applies them and the current Markdown rules to the
deliveries already prepared, without fetching anything again, and turns a delivery still in the old
one-JSON form, with its files in base64, into an archive.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from adapters.youtube import video_id_from_url
from importer import import_link
from markdown import first_heading, had_site_header, normalize, page_title, plain_title
from package import (
    Delivery,
    Video,
    delivery_name,
    link_delivery,
    package,
    read_delivery,
    stable_id,
    write_delivery,
    write_if_changed,
)
from web import LIVE

ALBUMS = Path(__file__).parent / "browser_albums.tsv"
COLLECTION_ALBUMS = {"UX/UI": "Design"}


def read_albums(path: Path = ALBUMS) -> dict[str, str]:
    """url → album from the reviewed table; a material without a row stays unsorted."""
    rows = path.read_text(encoding="utf-8").splitlines()[1:]
    return {url: album for album, _, _, _, url in (row.split("\t") for row in rows) if album}


def material_rows(library: dict, albums: dict[str, str]) -> list[dict]:
    collections = {item["id"]: item["name"] for item in library["collections"]}
    rows: dict[str, dict] = {}
    for source in library["sources"]:
        for material in source["materials"]:
            url = material["url"]
            row = rows.setdefault(url, {"url": url, "title": material["title"], "folders": set(), "sources": set()})
            if url in albums:
                row["folders"].add(albums[url])
            row["folders"].update(COLLECTION_ALBUMS[collections[name]] for name in material["saved_in"] if collections[name] in COLLECTION_ALBUMS)
            row["sources"].add(source["url"])
    return [
        {"url": row["url"], "title": row["title"], "folders": sorted(row["folders"]), "sources": sorted(row["sources"])}
        for row in rows.values()
    ]


def prepare(row: dict, output: Path, enrich_videos: bool = False, refetch: bool = False) -> tuple[str, str | None]:
    """Fetches one material. `refetch` reads a prepared web page again under the current rules; if the site
    no longer answers, or answers with less text than it gave before, the prepared delivery stays."""
    url = row["url"]
    destination = _article_path(output, url)
    if destination.exists() and not (
        enrich_videos and video_id_from_url(url) and not read_delivery(destination).package.get("body")
    ) and not (refetch and not video_id_from_url(url)):
        return url, None
    try:
        delivery = import_link(url, row["folders"], LIVE)
        if refetch:
            before = len(read_delivery(destination).package.get("body") or "")
            if len(delivery.package.get("body") or "") < before * 0.8:
                return url, "the page now gives less text; the prepared delivery stays"
        write_delivery(destination, delivery)
        return url, None
    except Exception as error:
        return url, str(error)


def link_unprepared(rows: list[dict], output: Path) -> int:
    """Every material that was never prepared becomes a link delivery, without asking its site again."""
    count = 0
    for row in rows:
        destination = _link_path(output, row["url"])
        if not destination.exists():
            write_delivery(destination, link_delivery(row["url"], row["title"], row["folders"]))
            count += 1
    return count


def _path(output: Path, material_id: str) -> Path:
    return output / "deliveries" / delivery_name(material_id)


def _claim_legacy(output: Path, target: Path, url: str, kind: str) -> Path:
    """A delivery prepared before the id rule is named by the URL; rename it to the id name, once."""
    legacy = output / "deliveries" / (hashlib.sha256(url.encode()).hexdigest() + ".tar")
    if target.exists() or not legacy.exists():
        return target
    if read_delivery(legacy).package["material"]["kind"] == kind:
        legacy.rename(target)
    return target


def _article_path(output: Path, url: str) -> Path:
    return _claim_legacy(output, _path(output, stable_id("article", url)), url, "article")


def _link_path(output: Path, url: str) -> Path:
    return _claim_legacy(output, _path(output, f"link:{url}"), url, "link")


def _old_delivery(path: Path) -> Delivery:
    """A delivery from before archives: one JSON with its files in base64 under `files`."""
    package = json.loads(path.read_text(encoding="utf-8"))
    files = {name: base64.b64decode(value) for name, value in package.pop("files", {}).items()}
    return Delivery(package, files)


def seed_videos(library: dict, rows: list[dict], output: Path) -> int:
    titles = {material["url"]: material["title"] for source in library["sources"] for material in source["materials"]}
    count = 0
    for row in rows:
        url = row["url"]
        video_id = video_id_from_url(url)
        if video_id is None:
            continue
        delivery = package(url, Video(video_id, titles[url]), row["folders"])
        destination = _claim_legacy(
            output, _path(output, delivery.package["material"]["id"]), url, "video"
        )
        if destination.exists():
            continue
        write_delivery(destination, delivery)
        count += 1
    return count


def repackage(rows: list[dict], output: Path) -> int:
    """Rewrites prepared deliveries with the current albums and Markdown rules; an old JSON delivery
    becomes an archive and the JSON goes."""
    count = 0
    for row in rows:
        url = row["url"]
        legacy = output / "deliveries" / hashlib.sha256(url.encode()).hexdigest()
        old = legacy.with_suffix(".json")
        if old.exists():
            prepared = _old_delivery(old)
            material = prepared.package["material"]
            material.setdefault("id", stable_id("article", url) if prepared.package.get("body") else f"link:{url}")
        elif legacy.with_suffix(".tar").exists():
            prepared = read_delivery(legacy.with_suffix(".tar"))
        else:
            continue
        delivery = prepared.package
        destination = _claim_legacy(
            output, _path(output, delivery["material"]["id"]), url, delivery["material"].get("kind", "article")
        )
        delivery["folders"] = row["folders"]
        if delivery.get("body"):
            if had_site_header(delivery["body"]) or delivery["material"]["title"] == row["title"]:
                # The old title came from the site's home link: take the article's own heading,
                # or the title the browser saved without the site name.
                body = normalize(delivery["body"])
                delivery["material"]["title"] = first_heading(body) or page_title(row["title"])
            delivery["body"] = normalize(delivery["body"])
            delivery["material"]["title"] = plain_title(delivery["material"]["title"])
        write_delivery(destination, prepared)
        old.unlink(missing_ok=True)
        count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare the browser library for FNMN")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--limit", type=int, help="Process only the first N materials")
    parser.add_argument("--kind", choices=("all", "web", "video"), default="all")
    parser.add_argument("--seed-videos", action="store_true", help="Create playable video records without fetching captions")
    parser.add_argument("--enrich-videos", action="store_true", help="Retry video records without captions")
    parser.add_argument("--repackage", action="store_true", help="Apply albums and Markdown rules to prepared deliveries")
    parser.add_argument("--links", action="store_true", help="Save every material not prepared yet as a link delivery, without fetching")
    parser.add_argument("--refetch", action="store_true", help="Read prepared web pages again; a page that fails keeps its delivery")
    args = parser.parse_args()
    library = json.loads(args.input.read_text(encoding="utf-8"))
    if library["review"] or library["errors"]:
        parser.error("resolve browser-library review and errors before preparation")
    rows = material_rows(library, read_albums())
    args.output.joinpath("deliveries").mkdir(parents=True, exist_ok=True)
    write_if_changed(args.output / "catalog.json", args.input.read_bytes())
    write_if_changed(args.output / "index.json", json.dumps(rows, ensure_ascii=False, indent=2).encode())
    if args.repackage:
        print(f"repackaged {repackage(rows, args.output)} deliveries")
        return
    if any(args.output.joinpath("deliveries").glob("*.json")):
        parser.error("deliveries are still one JSON each; run --repackage first, or they would be fetched again")
    if args.seed_videos:
        print(f"seeded {seed_videos(library, rows, args.output)} videos; existing deliveries kept")
        return
    if args.links:
        print(f"{link_unprepared(rows, args.output)} links")
        return
    selected = [row for row in rows if args.kind == "all" or ("video" if video_id_from_url(row["url"]) else "web") == args.kind]
    if args.refetch:
        # Only pages that were read before: a site that refused then is not asked again.
        selected = [row for row in selected if not video_id_from_url(row["url"]) and _delivery(args.output, row).exists()]
    if args.limit is not None:
        selected = selected[:args.limit]
    errors_path = args.output / ("errors.json" if args.kind == "all" else f"errors-{args.kind}.json")
    errors: dict[str, str] = json.loads(errors_path.read_text()) if errors_path.exists() else {}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(prepare, row, args.output, args.enrich_videos, args.refetch): row["url"] for row in selected}
        for count, job in enumerate(as_completed(jobs), 1):
            url, error = job.result()
            if error is None:
                errors.pop(url, None)
            elif not args.refetch:
                errors[url] = error
            errors_path.write_text(json.dumps(errors, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"{count}/{len(selected)} {'failed' if error else 'ready'} {url}", flush=True)
    ready = sum(_delivery(args.output, row).exists() for row in selected)
    print(f"{ready} ready, {len(selected) - ready} failed in selection, {len(rows)} unique materials", flush=True)


if __name__ == "__main__":
    main()

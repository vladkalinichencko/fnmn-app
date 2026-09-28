"""Prepare the materials in browser-library.json as FNMN deliveries.

    .venv/bin/python mac/prepare_browser_library.py browser-library.json prepared-browser-library

The command resumes from completed deliveries. Failed URLs remain in errors.json.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from adapters.youtube import video_id_from_url
from importer import import_link
from package import Video, package
from web import LIVE


def material_rows(library: dict) -> list[dict]:
    collections = {item["id"]: item["name"] for item in library["collections"]}
    rows: dict[str, dict] = {}
    for source in library["sources"]:
        for material in source["materials"]:
            url = material["url"]
            row = rows.setdefault(url, {"url": url, "folders": set(), "sources": set()})
            row["folders"].update(collections[name] for name in material["saved_in"])
            row["sources"].add(source["url"])
    return [
        {"url": row["url"], "folders": sorted(row["folders"]), "sources": sorted(row["sources"])}
        for row in rows.values()
    ]


def prepare(row: dict, output: Path, enrich_videos: bool = False) -> tuple[str, str | None]:
    url = row["url"]
    filename = hashlib.sha256(url.encode()).hexdigest() + ".json"
    destination = output / "deliveries" / filename
    if destination.exists() and not (
        enrich_videos and video_id_from_url(url) and not json.loads(destination.read_text()).get("body")
    ):
        return url, None
    try:
        delivery = import_link(url, row["folders"], LIVE)
        temporary = destination.with_suffix(".incoming")
        temporary.write_text(json.dumps(delivery, ensure_ascii=False), encoding="utf-8")
        temporary.replace(destination)
        return url, None
    except Exception as error:
        return url, str(error)


def seed_videos(library: dict, rows: list[dict], output: Path) -> int:
    titles = {material["url"]: material["title"] for source in library["sources"] for material in source["materials"]}
    count = 0
    for row in rows:
        url = row["url"]
        video_id = video_id_from_url(url)
        if video_id is None:
            continue
        destination = output / "deliveries" / (hashlib.sha256(url.encode()).hexdigest() + ".json")
        if destination.exists():
            continue
        delivery = package(url, Video(video_id, titles[url]), row["folders"])
        destination.write_text(json.dumps(delivery, ensure_ascii=False), encoding="utf-8")
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
    args = parser.parse_args()
    library = json.loads(args.input.read_text(encoding="utf-8"))
    if library["review"] or library["errors"]:
        parser.error("resolve browser-library review and errors before preparation")
    rows = material_rows(library)
    args.output.joinpath("deliveries").mkdir(parents=True, exist_ok=True)
    args.output.joinpath("catalog.json").write_text(args.input.read_text(encoding="utf-8"), encoding="utf-8")
    args.output.joinpath("index.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.seed_videos:
        print(f"seeded {seed_videos(library, rows, args.output)} videos; existing deliveries kept")
        return
    selected = [row for row in rows if args.kind == "all" or ("video" if video_id_from_url(row["url"]) else "web") == args.kind]
    if args.limit is not None:
        selected = selected[:args.limit]
    errors_path = args.output / ("errors.json" if args.kind == "all" else f"errors-{args.kind}.json")
    errors: dict[str, str] = json.loads(errors_path.read_text()) if errors_path.exists() else {}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(prepare, row, args.output, args.enrich_videos): row["url"] for row in selected}
        for count, job in enumerate(as_completed(jobs), 1):
            url, error = job.result()
            if error:
                errors[url] = error
            else:
                errors.pop(url, None)
            errors_path.write_text(json.dumps(errors, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"{count}/{len(selected)} {'failed' if error else 'ready'} {url}", flush=True)
    ready = sum((args.output / "deliveries" / (hashlib.sha256(row["url"].encode()).hexdigest() + ".json")).exists() for row in selected)
    print(f"{ready} ready, {len(selected) - ready} failed in selection, {len(rows)} unique materials", flush=True)


if __name__ == "__main__":
    main()

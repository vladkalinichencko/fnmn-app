"""Read every web page in the library again under the current parser, in the FNMN folder itself:

    cd server && ../.venv/bin/python -m collect.reparse_library \
        ~/Library/Mobile\\ Documents/com~apple~CloudDocs/FNMN

A material keeps its id, so it stays in its collections. The app forgets reading progress and marks of a
material whose text changed, so a material the reader marked read, noted, highlighted or read past its first
block, according to the journals in `state/`, is left as it is. So is a material the reader deleted: its archive may still be in the
folder, and a rewritten archive is newer than the deletion, which the app takes for the material coming back. A page that fails, or gives no text now, keeps the delivery it has.
A saved link whose page now reads as an article becomes that article, unless the article is already in the
folder or was deleted; the app moves the link's collections to it. `--into` writes the new deliveries to another folder to look at them first.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from importer import import_link
from package import Delivery, read_delivery, write_delivery
from web import LIVE

_KEPT_CHANGES = {"setRead", "note", "mark", "span", "delete"}


def touched(state: Path) -> set[str]:
    """Materials the reader marked read, annotated or deleted, from every device's journal."""
    materials: set[str] = set()
    for journal in state.glob("*.jsonl"):
        for line in journal.read_text(encoding="utf-8").splitlines():
            change = json.loads(line)["change"]
            ((_, wrapped),) = change.items()
            ((name, body),) = wrapped.get("_0", wrapped).items()
            if name in _KEPT_CHANGES or _moved_on(name, body):
                materials.update(_ids(body))
    return materials


def _moved_on(name: str, body: dict) -> bool:
    """A reading line, a "read through here" mark or a saved place anywhere past the first block."""
    place = body.get("_0")
    if name == "line":
        return bool(place) and (place["piece"] > 0 or place["fraction"] > 0)
    if name == "readThrough":
        return body.get("piece") is not None
    if name == "savePosition":
        return bool(place) and place.get("blockID") != "piece:0"
    return False


def _ids(value) -> set[str]:
    if isinstance(value, dict):
        found = {value[key] for key in ("itemID", "materialID") if isinstance(value.get(key), str)}
        for inner in value.values():
            found |= _ids(inner)
        return found
    if isinstance(value, list):
        return set().union(*(_ids(inner) for inner in value)) if value else set()
    return set()


def reparse(archive: Path, into: Path, kept: set[str]) -> str:
    """One delivery read again; returns what happened to it."""
    before = read_delivery(archive)
    material = before.package["material"]
    try:
        after = import_link(material["sourceURL"], before.package.get("folders") or [], LIVE)
    except Exception as error:
        return f"kept, {error}"
    if not (after.package.get("body") or "").strip():
        return "kept, no text"
    new = after.package["material"]
    if new["kind"] != "article":
        return f"kept, the page is now a {new['kind']}"
    if new["id"] == material["id"]:
        write_delivery(into / archive.name, after)
        return "reparsed"
    if material["kind"] == "link":
        if new["id"] in kept or (into / delivery_name(new["id"])).exists():
            return f"kept, {new['id']} is already in the library or was deleted"
        write_delivery(into / delivery_name(new["id"]), after)
        return "link became an article"
    return f"kept, id changed to {new['id']}"


def delivery_name(material_id: str) -> str:
    """The app's name for a material's archive."""
    return hashlib.sha256(material_id.encode()).hexdigest() + ".tar"


def main() -> None:
    parser = argparse.ArgumentParser(description="Reparse the web pages of the FNMN library")
    parser.add_argument("library", type=Path, help="the FNMN folder in iCloud Drive")
    parser.add_argument("--into", type=Path, help="write the new deliveries here instead of the library")
    parser.add_argument("--only", action="append", default=[], help="a source URL to reparse; repeatable")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    deliveries = args.library / "deliveries"
    into = args.into or deliveries
    kept = touched(args.library / "state")
    selected: list[Path] = []
    for archive in sorted(deliveries.glob("*.tar")):
        material = read_delivery(archive).package["material"]
        if material["kind"] not in {"article", "link"} or material["id"] in kept:
            continue
        if args.only and material.get("sourceURL") not in args.only:
            continue
        selected.append(archive)
    print(f"{len(selected)} to read, {len(kept)} read, annotated, deleted or started by the reader left as they are", flush=True)
    log = (args.into or Path.cwd()) / "reparse.json"
    results: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(reparse, archive, into, kept): archive for archive in selected}
        for count, job in enumerate(as_completed(jobs), 1):
            archive = jobs[job]
            try:
                result = job.result()
            except Exception as error:
                result = f"kept, {error}"
            url = read_delivery(archive).package["material"].get("sourceURL") or archive.name
            results[url] = result
            log.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"{count}/{len(selected)} {result[:80]} {url}", flush=True)


if __name__ == "__main__":
    main()

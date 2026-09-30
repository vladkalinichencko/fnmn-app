"""Export Safari Reading List, Safari tab groups, and Dia bookmarks to CSV.

    python3 server/browser_links_export.py -o browser-links.csv

Each row keeps its source, Dia profile, and bookmark folder path. The script
reads browser files without changing them; it does not export Dia tab groups.
"""

import argparse
import csv
import json
import plistlib
import sqlite3
import sys
from pathlib import Path


FIELDS = ("source", "profile", "folder", "title", "url")


def safari_reading_list(path: Path):
    bookmarks = plistlib.loads(path.read_bytes())
    reading_list = next(
        child for child in bookmarks["Children"]
        if child.get("Title") == "com.apple.ReadingList"
    )
    for item in reading_list["Children"]:
        if url := item.get("URLString"):
            yield {"source": "Safari Reading List", "profile": "", "folder": "",
                   "title": item.get("URIDictionary", {}).get("title", ""), "url": url}


def safari_tab_groups(path: Path, names: set[str] | None = None):
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        groups = connection.execute(
            "SELECT id, title FROM bookmarks WHERE type = 1 AND deleted = 0"
        ).fetchall()
        for group_id, title in groups:
            if names is not None and title not in names:
                continue
            for tab_title, url in connection.execute(
                "SELECT title, url FROM bookmarks "
                "WHERE parent = ? AND type = 0 AND deleted = 0 ORDER BY order_index, id",
                (group_id,),
            ):
                if url and url.startswith(("http://", "https://")):
                    yield {"source": "Safari Tab Groups", "profile": "", "folder": title,
                           "title": tab_title or "", "url": url}
    finally:
        connection.close()


def dia_bookmarks(user_data: Path):
    state = json.loads((user_data / "Local State").read_text())
    names = state["profile"]["info_cache"]
    for profile_dir in sorted(user_data.glob("Profile *")):
        path = profile_dir / "Bookmarks"
        if not path.exists():
            continue
        profile = names.get(profile_dir.name, {}).get("name", profile_dir.name)
        roots = json.loads(path.read_text())["roots"]
        for root in roots.values():
            if isinstance(root, dict):
                yield from dia_folder(root, profile, ())


def dia_folder(node: dict, profile: str, folders: tuple[str, ...]):
    if node.get("type") == "url":
        if url := node.get("url"):
            yield {"source": "Dia bookmarks", "profile": profile,
                   "folder": "/".join(folders), "title": node.get("name", ""), "url": url}
        return
    if node.get("type") == "folder":
        folders = (*folders, node.get("name", ""))
        for child in node.get("children", []):
            yield from dia_folder(child, profile, folders)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", type=Path, help="CSV file; default: stdout")
    parser.add_argument("--safari", type=Path, default=Path.home() / "Library/Safari/Bookmarks.plist")
    parser.add_argument("--dia", type=Path, default=Path.home() / "Library/Application Support/Dia/User Data")
    args = parser.parse_args()

    rows = list(safari_reading_list(args.safari)) + list(dia_bookmarks(args.dia))
    if args.output:
        with args.output.open("w", newline="", encoding="utf-8") as output:
            writer = csv.DictWriter(output, FIELDS)
            writer.writeheader()
            writer.writerows(rows)
    else:
        writer = csv.DictWriter(sys.stdout, FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"exported {len(rows)} links", file=sys.stderr)


if __name__ == "__main__":
    main()

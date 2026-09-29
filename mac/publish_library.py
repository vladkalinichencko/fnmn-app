"""Lay out the folder the phone imports in one pass: the prepared browser library and the books.

    .venv/bin/python mac/publish_library.py prepared-browser-library fixtures/books/principles-of-deep-learning-theory \
        ~/Library/Mobile\\ Documents/com~apple~CloudDocs/FNMN

The destination gets `catalog.json`, `deliveries/` and `books/<name>/`. Book text goes through the same
Markdown rules as every package, so a formula inside a sentence stays in its paragraph.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from markdown import normalize


def publish(prepared: Path, books: list[Path], destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(prepared / "catalog.json", destination / "catalog.json")
    # Replaced whole: copying over the old files makes iCloud keep both as "name 2.json".
    shutil.rmtree(destination / "deliveries", ignore_errors=True)
    shutil.copytree(prepared / "deliveries", destination / "deliveries")
    for book in books:
        target = destination / "books" / book.name
        shutil.copytree(book, target, dirs_exist_ok=True)
        content = target / "content.md"
        content.write_text(normalize(content.read_text(encoding="utf-8")), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Lay out the FNMN import folder")
    parser.add_argument("prepared", type=Path)
    parser.add_argument("books", type=Path, nargs="*")
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    publish(args.prepared, args.books, args.destination)


if __name__ == "__main__":
    main()

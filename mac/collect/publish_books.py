"""Put prepared books into the FNMN folder in iCloud Drive, beside the deliveries prepare_browser_library writes there.

    cd mac && ../.venv/bin/python -m collect.publish_books ../fixtures/books/principles-of-deep-learning-theory \
        ~/Library/Mobile\\ Documents/com~apple~CloudDocs/FNMN

Each book lands in `books/<name>/`. Book text goes through the same Markdown rules as every package, so a
formula inside a sentence stays in its paragraph. Only files that changed are written, and a file the book
no longer has is removed, so iCloud uploads and deletes only what differs.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from markdown import normalize
from package import write_if_changed


def publish(books: list[Path], destination: Path) -> None:
    for book in books:
        target = destination / "books" / book.name
        kept = set()
        for source in sorted(path for path in book.rglob("*") if path.is_file()):
            relative = source.relative_to(book)
            blob = source.read_bytes()
            if relative == Path("content.md"):
                blob = normalize(blob.decode("utf-8")).encode("utf-8")
            write_if_changed(target / relative, blob)
            kept.add(relative)
        for stale in (path for path in target.rglob("*") if path.is_file()):
            if stale.relative_to(target) not in kept:
                stale.unlink()


def main() -> None:
    parser = argparse.ArgumentParser(description="Put prepared books into the FNMN folder")
    parser.add_argument("books", type=Path, nargs="+")
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    publish(args.books, args.destination)


if __name__ == "__main__":
    main()

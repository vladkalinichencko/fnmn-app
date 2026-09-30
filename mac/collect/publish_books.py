"""Put books the PDF pipeline exported into the FNMN folder in iCloud Drive, as deliveries like any other material.

    cd mac && ../.venv/bin/python -m collect.publish_books ../fixtures/books/principles-of-deep-learning-theory \
        ~/Library/Mobile\\ Documents/com~apple~CloudDocs/FNMN

Each book becomes one archive in `deliveries/`, and its PDF, found by the name the book records in
`--originals` (Apple Books by default), goes to `originals/` beside it. Book text goes through the same Markdown
rules as every package, so a formula inside a sentence stays in its paragraph. An unchanged file is not written again.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from markdown import normalize
from package import book_delivery, delivery_name, place_original, write_delivery

APPLE_BOOKS = Path.home() / "Library/Mobile Documents/iCloud~com~apple~iBooks/Documents"


def publish(books: list[Path], destination: Path, originals: Path = APPLE_BOOKS) -> None:
    for book in books:
        delivery = book_delivery(book)
        delivery.package["body"] = normalize(delivery.package["body"])
        name = delivery_name(delivery.package["material"]["id"])
        write_delivery(destination / "deliveries" / name, delivery)
        pdf = originals / json.loads((book / "metadata.json").read_text(encoding="utf-8"))["source_name"]
        if pdf.is_file():
            place_original(destination, name, pdf)
        else:
            print(f"{book.name}: no original at {pdf}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Put exported books into the FNMN folder")
    parser.add_argument("books", type=Path, nargs="+")
    parser.add_argument("destination", type=Path)
    parser.add_argument("--originals", type=Path, default=APPLE_BOOKS, help="folder holding each book's PDF")
    args = parser.parse_args()
    publish(args.books, args.destination, args.originals)


if __name__ == "__main__":
    main()

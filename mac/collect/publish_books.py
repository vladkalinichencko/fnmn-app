"""Put books the PDF pipeline exported into the FNMN folder in iCloud Drive, as deliveries like any other material.

    cd mac && ../.venv/bin/python -m collect.publish_books ../fixtures/books/principles-of-deep-learning-theory \
        ~/Library/Mobile\\ Documents/com~apple~CloudDocs/FNMN

Each book becomes one archive in `deliveries/`. Book text goes through the same Markdown rules as every package,
so a formula inside a sentence stays in its paragraph. An unchanged book is not written again.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from markdown import normalize
from package import book_delivery, delivery_name, write_delivery


def publish(books: list[Path], destination: Path) -> None:
    for book in books:
        delivery = book_delivery(book)
        delivery.package["body"] = normalize(delivery.package["body"])
        write_delivery(destination / "deliveries" / delivery_name(delivery.package["material"]["id"]), delivery)


def main() -> None:
    parser = argparse.ArgumentParser(description="Put exported books into the FNMN folder")
    parser.add_argument("books", type=Path, nargs="+")
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    publish(args.books, args.destination)


if __name__ == "__main__":
    main()

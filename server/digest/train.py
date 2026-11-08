"""Train the digest's on-device topic classifier from the posts the store keeps and the engagement the phones
wrote back.

    python -m digest.train [--folder PATH] [--root PATH] [--dry-run]

A post labels with its source's first folder. A post the reader hid is left out of training; a post the reader
saved counts three times, a post the reader opened twice. The result is one CoreML text classifier,
`out/classifier.mlmodel`, which the next digest carries and the phone runs with NLModel. Too few labeled posts
is a normal early state: the digest then goes without a model and the magazine groups posts by their sources.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from digest.store import Store, iso

HERE = Path(__file__).resolve().parent
FNMN = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/FNMN"
MINIMUM = 20


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Train the digest's text classifier")
    parser.add_argument("--folder", default=str(FNMN))
    parser.add_argument("--root", default=None, help="the store's folder, for tests")
    parser.add_argument("--dry-run", action="store_true", help="report the rows without training")
    options = parser.parse_args(argv)
    store = Store(Path(options.root)) if options.root else Store()
    texts, labels = rows(store, engagement(Path(options.folder)))
    print(f"{len(texts)} rows from {dict(Counter(labels))}")
    if len(texts) < MINIMUM:
        print(f"fewer than {MINIMUM} labeled posts; the digest goes without a classifier this time")
        return 0
    if len(set(labels)) < 2:
        print("only one folder has posts; a classifier needs at least two")
        return 0
    if options.dry_run:
        return 0
    train(texts, labels)
    return 0


def rows(store: Store, events: list[dict]) -> tuple[list[str], list[str]]:
    """The training rows: (text, folder), repeated by how much attention the reader gave the post."""
    marks: dict[str, set[str]] = {}
    for event in events:
        marks.setdefault(event["postID"], set()).add(event["kind"])
    texts: list[str] = []
    labels: list[str] = []
    for post in store.posts():
        if not post.text or not post.folders:
            continue
        kinds = marks.get(post.id, set())
        if "hidden" in kinds:
            continue
        weight = 3 if "saved" in kinds else 2 if "opened" in kinds else 1
        for _ in range(weight):
            texts.append(post.text[:2000])
            labels.append(post.folders[0])
    return texts, labels


def engagement(folder: Path) -> list[dict]:
    """Every event every device wrote, oldest or newest, they all repeat the same post the same way."""
    state = folder / "digest-state"
    if not state.exists():
        return []
    events = []
    for journal in state.glob("*.jsonl"):
        for line in journal.read_text(encoding="utf-8").splitlines():
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def train(texts: list[str], labels: list[str]) -> None:
    """Writes the rows where the Swift trainer reads them, trains, and keeps the model with when and on what
    it was trained. The rows file holds post texts, so it is deleted once the model is written."""
    out = HERE / "out"
    out.mkdir(parents=True, exist_ok=True)
    rows_file = out / "train-rows.json"
    rows_file.write_text(
        json.dumps([{"text": text, "label": label} for text, label in zip(texts, labels)], ensure_ascii=False),
        encoding="utf-8",
    )
    try:
        subprocess.run(
            ["swift", str(HERE / "classifier/Train.swift"), str(rows_file), str(out / "classifier.mlmodel")],
            check=True,
        )
    finally:
        rows_file.unlink(missing_ok=True)
    (out / "model.json").write_text(
        json.dumps({
            "trained_at": iso(datetime.now(timezone.utc)),
            "examples": len(texts),
            "folders": sorted(set(labels)),
        }, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"{out / 'classifier.mlmodel'}: {len(texts)} rows")


if __name__ == "__main__":
    raise SystemExit(main())

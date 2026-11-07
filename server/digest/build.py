"""Pack the posts collected since the last digest into one delivery in the FNMN folder.

    python -m digest.build [--folder PATH] [--force] [--now ISO]

The builder runs from the launchd agent twice a day, at 08:00 and 20:00 local time: a run that is not due, or
that has nothing new, writes nothing. The delivery is the same uncompressed USTAR archive as an article's,
`package.json` first, and lands under `digests/` in the FNMN folder, where the phone reads it the way it reads
every other delivery.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import tarfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

from digest.store import Post, Store, iso, wire

HERE = Path(__file__).resolve().parent
FNMN = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/FNMN"
BUILD_HOURS = (8, 20)
KEEP = 14


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pack the new posts into a digest delivery")
    parser.add_argument("--folder", default=str(FNMN))
    parser.add_argument("--root", default=None, help="the store's folder, for tests")
    parser.add_argument("--now", default=None, help="ISO time to build as, for tests")
    parser.add_argument("--force", action="store_true", help="build even when the schedule is not due")
    options = parser.parse_args(argv)
    now = datetime.fromisoformat(options.now) if options.now else datetime.now(timezone.utc)
    store = Store(Path(options.root)) if options.root else Store()
    pending = store.unconsumed()
    if not pending:
        print("nothing new since the last digest")
        return 0
    if not options.force and not due(store, now):
        print("the next build time has not come yet")
        return 0
    for post in pending:
        _check(post)
    package = _package(pending, store, _subscriptions(), now)
    folder = Path(options.folder) / "digests"
    folder.mkdir(parents=True, exist_ok=True)
    name = f"{package['id']}.tar"
    _write(package, pending, store, folder / name)
    store.record_build({"id": package["id"], "at": iso(now), "post_ids": [post.id for post in pending], "file": name})
    _prune(folder)
    print(f"{folder / name}: {len(pending)} posts")
    return 0


def due(store: Store, now: datetime) -> bool:
    last = store.last_build_at()
    return last is None or next_build_time(last) <= now


def next_build_time(after: datetime) -> datetime:
    """The first scheduled time strictly after `after`, in the Mac's own time zone."""
    local = after.astimezone()
    for hour in BUILD_HOURS:
        candidate = local.replace(hour=hour, minute=0, second=0, microsecond=0)
        if candidate > local:
            return candidate
    tomorrow = local + timedelta(days=1)
    return tomorrow.replace(hour=BUILD_HOURS[0], minute=0, second=0, microsecond=0)


def _subscriptions() -> dict:
    return json.loads((HERE / "subscriptions.json").read_text(encoding="utf-8"))


def _package(posts: list[Post], store: Store, subscriptions: dict, now: datetime) -> dict:
    last = store.last_build_at()
    start = last or min(datetime.fromisoformat(post.posted_at) for post in posts)
    return {
        "schema": 1,
        "id": f"digest-{now.astimezone(timezone.utc):%Y-%m-%dT%H-%M-%SZ}",
        "window": {"from": iso(start), "to": iso(now)},
        "folders": subscriptions["folders"],
        "sources": store.source_statuses(),
        "model": _model(),
        "posts": [wire(post) for post in sorted(posts, key=lambda post: post.posted_at, reverse=True)],
    }


def _model() -> dict | None:
    """The classifier the last training wrote, when it is there."""
    manifest = HERE / "out/model.json"
    classifier = HERE / "out/classifier.mlmodel"
    if not manifest.exists() or not classifier.exists():
        return None
    trained = json.loads(manifest.read_text(encoding="utf-8"))
    return {"file": "classifier.mlmodel", "trainedAt": trained["trained_at"], "examples": trained["examples"]}


def _write(package: dict, posts: list[Post], store: Store, destination: Path) -> None:
    """Writes the delivery next to its final name and renames it into place, so a run that dies leaves no
    half a digest for the phone to read."""
    temporary = destination.with_suffix(".tar.part")
    with tarfile.open(temporary, "w", format=tarfile.USTAR_FORMAT) as archive:
        _add(archive, "package.json", json.dumps(package, ensure_ascii=False).encode("utf-8"))
        for post in posts:
            for media in post.media:
                _add_path(archive, media["path"], store.root / media["path"])
            poster = (post.video or {}).get("poster")
            if poster:
                _add_path(archive, poster["path"], store.root / poster["path"])
        model = HERE / "out/classifier.mlmodel"
        if package["model"] and model.exists():
            _add_path(archive, "classifier.mlmodel", model)
    os.replace(temporary, destination)


def _add(archive: tarfile.TarFile, name: str, data: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    archive.addfile(info, io.BytesIO(data))


def _add_path(archive: tarfile.TarFile, name: str, path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"the digest names {name}, which the store does not hold")
    info = archive.gettarinfo(str(path), arcname=name)
    info.mode = 0o644
    with path.open("rb") as file:
        archive.addfile(info, file)


def _check(post: Post) -> None:
    """A post the magazine cannot show is a source bug, and the build stops on it instead of shipping a card
    that opens nothing."""
    if not post.permalink:
        raise ValueError(f"{post.id} has no permalink")
    if not post.text and not post.media and not post.video:
        raise ValueError(f"{post.id} has neither text nor media")


def _prune(folder: Path) -> None:
    deliveries = sorted(folder.glob("digest-*.tar"))
    for old in deliveries[:-KEEP]:
        old.unlink()


if __name__ == "__main__":
    raise SystemExit(main())

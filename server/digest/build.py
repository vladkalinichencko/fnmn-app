"""Pack the posts collected since the last digest into one delivery in the FNMN folder.

    python -m digest.build [--folder PATH] [--force] [--now ISO]

The builder runs from the launchd agent twice a day, at 08:00 and 20:00 local time: a run that is not due, or
that has nothing new, writes nothing. The delivery is the same uncompressed USTAR archive as an article's,
`package.json` first, and lands under `digests/` in the FNMN folder, where the phone reads it the way it reads
every other delivery.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from digest.store import Post, Store, iso, wire
from package import write_delivery_from

HERE = Path(__file__).resolve().parent
FNMN = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/FNMN"
BUILD_HOURS = (8, 20)
KEEP = 14


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pack the new posts into a digest delivery")
    parser.add_argument("--folder", default=str(FNMN))
    parser.add_argument("--root", default=None, help="the store's folder, for tests")
    parser.add_argument("--subscriptions", default=None, help="the subscriptions file, for tests")
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
    subscriptions = _subscriptions(Path(options.subscriptions) if options.subscriptions else HERE / "subscriptions.json")
    skipped = {}
    for post in pending:
        reason = _unshowable(post) or _available(post, store)
        if reason:
            skipped[post.id] = reason
    buildable = [post for post in pending if post.id not in skipped]
    if not buildable:
        store.record_build({"at": iso(now), "post_ids": list(skipped), "skipped": skipped, "file": None})
        for post_id, reason in skipped.items():
            print(f"{post_id}: skipped: {reason}")
        print("nothing showable to build")
        return 0
    package = _package(buildable, store, subscriptions, now)
    folder = Path(options.folder) / "digests"
    folder.mkdir(parents=True, exist_ok=True)
    name = f"{package['id']}.tar"
    _write(package, buildable, store, folder / name)
    store.record_build({
        "id": package["id"],
        "at": iso(now),
        "post_ids": [post.id for post in pending],
        "skipped": skipped,
        "file": name,
    })
    _prune(folder)
    for post_id, reason in skipped.items():
        print(f"{post_id}: skipped: {reason}")
    print(f"{folder / name}: {len(buildable)} posts")
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


def _subscriptions(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


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
    """The delivery goes through the same writer as an article's; the files already live in the store."""
    files: list[tuple[str, Path]] = []
    for post in posts:
        files += [(media["path"], store.root / media["path"]) for media in post.media]
        poster = (post.video or {}).get("poster")
        if poster:
            files.append((poster["path"], store.root / poster["path"]))
        for comment in post.comments:
            avatar = comment.get("avatar")
            if avatar:
                files.append((avatar["path"], store.root / avatar["path"]))
    model = HERE / "out/classifier.mlmodel"
    if package["model"] and model.exists():
        files.append(("classifier.mlmodel", model))
    write_delivery_from(destination, package, files)


def _unshowable(post: Post) -> str | None:
    """Why the magazine would draw a card that opens nothing; `None` when it would draw a real one."""
    if not post.permalink:
        return "no permalink"
    if post.text or post.media or post.media_errors:
        return None
    if post.video and post.video.get("poster"):
        return None
    if post.video:
        return "a video with no poster"
    return "neither text nor media"


def _available(post: Post, store: Store) -> str | None:
    """Drops a picture the store does not hold; a post left with nothing to draw is skipped like an empty one."""
    available = []
    for media in post.media:
        if (store.root / media["path"]).exists():
            available.append(media)
        else:
            print(f"{post.id}: missing {media['path']}")
    post.media = available
    poster = (post.video or {}).get("poster")
    if poster and not (store.root / poster["path"]).exists():
        print(f"{post.id}: missing {poster['path']}")
        post.video["poster"] = None
    if post.text or post.media or post.media_errors or (post.video and post.video.get("poster")):
        return None
    return "missing media"


def _prune(folder: Path) -> None:
    deliveries = sorted(folder.glob("digest-*.tar"))
    for old in deliveries[:-KEEP]:
        old.unlink()


if __name__ == "__main__":
    raise SystemExit(main())

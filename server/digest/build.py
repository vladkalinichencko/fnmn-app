"""Pack the posts collected since the last digest into one delivery in the REED folder.

    python -m digest.build [--folder PATH] [--force] [--now ISO]

The builder runs from the launchd agent at the hours in the settings: a run that is not due, or
that has nothing new, writes nothing. `limit` is the pool every post competes for in one
delivery, and each author's next story counts half of the one before, so one loud author cannot
fill it; a settings file without topics collects the whole feed under the `FEED_LIMIT` ceiling.
A `rotation` block in the settings (`sources`, `posts`) ships only the longest-waiting channels'
best posts each build.
The delivery is the same
uncompressed USTAR archive as an article's,
`package.json` first, and lands under `digests/` in the REED folder, where the phone reads it the way it reads
every other delivery.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path

from digest import settings as digest_settings
from digest import subscriptions, topics
from digest.store import Post, Store, flat_text, iso, prefix_of, wire
from package import write_delivery_from

BUILD_HOURS = (8, 20)
KEEP = 4
FEED_LIMIT = 40
AUTHOR_DECAY = 0.5


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pack the new posts into a digest delivery")
    parser.add_argument("--folder", default=str(digest_settings.REED))
    parser.add_argument("--root", default=None, help="the store's folder, for tests")
    parser.add_argument("--subscriptions", default=None, help="the subscriptions file, for tests")
    parser.add_argument("--now", default=None, help="ISO time to build as, for tests")
    parser.add_argument("--force", action="store_true", help="build even when the schedule is not due")
    options = parser.parse_args(argv)
    prefs = digest_settings.load(Path(options.folder))
    if not prefs["enabled"]:
        print("the digest is off in its settings")
        return 0
    now = datetime.fromisoformat(options.now) if options.now else datetime.now(timezone.utc)
    store = Store(Path(options.root)) if options.root else Store()
    folder = Path(options.folder) / "digests"
    pending = store.unconsumed(deliveries=folder)
    if not pending:
        print("nothing new since the last digest")
        return 0
    if not options.force and not due(store, now, prefs):
        print("the next build time has not come yet")
        return 0
    subscription_data = subscriptions.load(Path(options.subscriptions) if options.subscriptions else None)
    skipped = {}
    for post in pending:
        reason = _unshowable(post) or _available(post, store)
        if reason:
            skipped[post.id] = reason
    buildable = [post for post in pending if post.id not in skipped]
    buildable, text_over = _dedup_texts(buildable)
    skipped.update(text_over)
    scores = topics.classify(_threads(buildable), prefs)
    filtered = []
    for thread in _threads(buildable):
        if _below_threshold(thread, prefs):
            for post in thread:
                skipped[post.id] = "below the topic threshold"
        else:
            filtered.extend(thread)
    buildable = filtered
    scores = _author_decay(_threads(buildable), scores)
    per_source: dict[str, list[list[Post]]] = {}
    for thread in _threads(buildable):
        per_source.setdefault(thread[0].source, []).append(thread)
    kept, over = [], {}
    for source_id, group in per_source.items():
        group_kept, group_over = topics.cap(group, scores, digest_settings.source_limit(prefs, source_id) or prefs["limit"])
        kept += group_kept
        over.update(group_over)
    buildable = kept
    net_kept, net_over = _cap_networks(buildable, scores, prefs)
    buildable = net_kept
    over.update(net_over)
    rotated, rot_over = _rotate(buildable, scores, store, prefs.get("rotation") or {})
    buildable = rotated
    over.update(rot_over)
    ranked, rank_over = _cap_ranked(buildable, scores, prefs)
    buildable = ranked
    over.update(rank_over)
    if not digest_settings.any_topics(prefs):
        buildable, feed_over = topics.cap(_threads(buildable), scores, FEED_LIMIT)
        over.update(feed_over)
    skipped.update(over)
    if not buildable:
        store.record_build({"at": iso(now), "post_ids": list(skipped), "skipped": skipped, "file": None})
        for post_id, reason in skipped.items():
            print(f"{post_id}: skipped: {reason}")
        print("nothing showable to build")
        return 0
    package = _package(buildable, store, subscription_data, now)
    folder.mkdir(parents=True, exist_ok=True)
    name = f"{package['id']}.tar"
    store.record_build({"at": iso(now), "post_ids": [post.id for post in pending], "file": name, "pending": True})
    try:
        _write(package, buildable, store, folder / name)
        store.record_build({
            "id": package["id"],
            "at": iso(now),
            "post_ids": [post.id for post in pending],
            "skipped": skipped,
            "file": name,
        })
    except Exception:
        (folder / name).unlink(missing_ok=True)
        raise
    _prune(folder)
    for post_id, reason in skipped.items():
        print(f"{post_id}: skipped: {reason}")
    print(f"{folder / name}: {len(buildable)} posts")
    return 0


def due(store: Store, now: datetime, prefs: dict | None = None) -> bool:
    last = store.last_build_at()
    hours = digest_settings.hours(prefs) if prefs else BUILD_HOURS
    return last is None or next_build_time(last, hours) <= now


def next_build_time(after: datetime, hours: tuple[int, ...] = BUILD_HOURS) -> datetime:
    """The first scheduled time strictly after `after`, in the Mac's own time zone."""
    local = after.astimezone()
    for hour in hours:
        candidate = local.replace(hour=hour, minute=0, second=0, microsecond=0)
        if candidate > local:
            return candidate
    tomorrow = local + timedelta(days=1)
    return tomorrow.replace(hour=hours[0], minute=0, second=0, microsecond=0)


def _below_threshold(thread: list[Post], prefs: dict) -> bool:
    """The threshold verdict belongs to the story, not to one message of it: `classify` gives every
    member the same folders, so a thread under the bar drops whole instead of leaving its textless
    posts to ship without the text that explained them."""
    first = thread[0]
    return (
        bool(digest_settings.topics(prefs, first.network, first.source))
        and any(post.text for post in thread)
        and all(not post.folders for post in thread)
    )


def _dedup_texts(posts: list[Post]) -> tuple[list[Post], dict[str, str]]:
    """One story, one card: a channel that reposts its text as a media caption leaves a cut copy
    beside the whole one. The delivery keeps the longer text and moves the cut copy's media onto
    it, so the pictures survive without the duplicate card."""
    kept: list[Post] = []
    flats: list[tuple[str, str, str, Post]] = []
    seen: dict[str, Post] = {}
    over: dict[str, str] = {}
    for post in sorted(posts, key=lambda item: len(flat_text(item.text)), reverse=True):
        if post.id in seen:
            survivor = seen[post.id]
            _merge_attachments(survivor, post)
            over[post.id] = "a duplicate row"
            continue
        seen[post.id] = post
        flat = flat_text(post.text)
        twin = next(
            (entry for entry in flats if entry[0] == post.network and entry[1] == post.source and (entry[2] == flat or prefix_of(flat, entry[2]))),
            None,
        )
        if twin is not None:
            survivor = twin[3]
            _merge_attachments(survivor, post)
            over[post.id] = "the same text" if twin[2] == flat else "a shorter copy of the same text"
            continue
        kept.append(post)
        if flat:
            flats.append((post.network, post.source, flat, post))
    return kept, over


def _author_key(post: Post) -> tuple[str, str]:
    """Who wrote the post: the handle, so an author met inside the recommendations feed counts
    the same as in their own channel; the source stands in when there is no handle."""
    return (post.network, (post.author or {}).get("handle") or post.source)


def _base_score(post: Post, scores: dict[str, float]) -> float:
    """The post's topic score; a post that never entered the vote scores 0 and ranks last,
    the way it did before the decay existed."""
    return scores.get(post.id, 0.0)


def _author_decay(threads: list[list[Post]], scores: dict[str, float]) -> dict[str, float]:
    """Each author's stories rank by their own score, best first, and every next one counts
    `AUTHOR_DECAY` of the one before: an author's first post ships whole, his fifth rarely does,
    with no hard per-author cap. The adjustment covers every post, so the network, source and
    rotation caps all rank by the same decayed score."""
    by_author: dict[tuple[str, str], list[list[Post]]] = {}
    for thread in threads:
        by_author.setdefault(_author_key(thread[0]), []).append(thread)
    adjusted: dict[str, float] = {}
    for author_threads in by_author.values():
        ordered = sorted(
            author_threads,
            key=lambda thread: (max(_base_score(post, scores) for post in thread), max(post.posted_at for post in thread)),
            reverse=True,
        )
        for rank, thread in enumerate(ordered):
            factor = AUTHOR_DECAY ** rank
            for post in thread:
                adjusted[post.id] = _base_score(post, scores) * factor
    return adjusted


def _cap_ranked(posts: list[Post], scores: dict[str, float], prefs: dict) -> tuple[list[Post], dict[str, str]]:
    """The delivery's `limit` is the pool the classified posts compete for across every source:
    without it each source ships its own quota and the loudest author fills the digest. Posts
    from networks without topics never entered the vote and ship as before."""
    threads = _threads(posts)
    ranked = [thread for thread in threads if max(scores.get(post.id, 0.0) for post in thread) > 0]
    if not ranked:
        return posts, {}
    kept_posts, over = topics.cap(ranked, scores, prefs["limit"])
    kept_ids = {post.id for post in kept_posts}
    ranked_ids = {post.id for thread in ranked for post in thread}
    return [post for post in posts if post.id not in ranked_ids or post.id in kept_ids], over


def _threads(posts: list[Post]) -> list[list[Post]]:
    """The posts grouped by their collected thread; a post without one is a thread of one."""
    groups: dict[str, list[Post]] = {}
    order: list[str] = []
    for post in posts:
        key = post.thread or post.id
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(post)
    return [groups[key] for key in order]


def _cap_networks(posts: list[Post], scores: dict[str, float], prefs: dict) -> tuple[list[Post], dict[str, str]]:
    """A network that names a `limit` in the settings ships at most that many posts a delivery,
    the strongest threads first; the rest is consumed but not shipped."""
    limited = {post.network for post in posts if digest_settings.network_limit(prefs, post.network)}
    if not limited:
        return posts, {}
    by_network: dict[str, list[list[Post]]] = {}
    for thread in _threads(posts):
        by_network.setdefault(thread[0].network, []).append(thread)
    kept: list[Post] = []
    over: dict[str, str] = {}
    for network, groups in by_network.items():
        limit = digest_settings.network_limit(prefs, network)
        if limit is None:
            kept += [post for group in groups for post in group]
            continue
        group_kept, group_over = topics.cap(groups, scores, limit)
        kept += group_kept
        over.update(group_over)
    return kept, over


def _rotate(posts: list[Post], scores: dict[str, float], store: Store, rotation: dict) -> tuple[list[Post], dict[str, str]]:
    """A delivery that names `rotation` ships only the strongest `posts` posts of the `sources`
    channels that went the longest without one, per network — the networks' score scales differ,
    so one shared pool would starve the quieter ones. Every other post is consumed but not
    shipped, so each channel gets its turn instead of the whole firehose landing at once."""
    sources_n = rotation.get("sources")
    posts_n = rotation.get("posts")
    if not isinstance(sources_n, int) or not isinstance(posts_n, int) or sources_n <= 0 or posts_n <= 0:
        return posts, {}
    builds = [build for build in store.builds() if not build.get("pending")]
    source_of = {post.id: post.source for post in store.posts()}
    last_shipped: dict[str, int] = {}
    for index, build in enumerate(builds):
        shipped = set(build.get("post_ids", [])) - set((build.get("skipped") or {}).keys())
        for post_id in shipped:
            source = source_of.get(post_id)
            if source:
                last_shipped[source] = index
    by_network: dict[str, list[Post]] = {}
    for post in posts:
        by_network.setdefault(post.network, []).append(post)
    kept: list[Post] = []
    over: dict[str, str] = {}
    for group in by_network.values():
        group_kept, group_over = _rotate_network(group, scores, last_shipped, sources_n, posts_n)
        kept += group_kept
        over.update(group_over)
    return kept, over


def _rotate_network(
    posts: list[Post], scores: dict[str, float], last_shipped: dict[str, int], sources_n: int, posts_n: int
) -> tuple[list[Post], dict[str, str]]:
    by_source: dict[str, list[list[Post]]] = {}
    for thread in _threads(posts):
        by_source.setdefault(thread[0].source, []).append(thread)

    def rank(source: str) -> tuple[int, float]:
        best = max(
            (scores.get(post.id, 0.0) for group in by_source[source] for post in group),
            default=0.0,
        )
        return (last_shipped.get(source, -1), -best)

    ordered = sorted(by_source, key=rank)
    kept: list[Post] = []
    over: dict[str, str] = {}
    for source in ordered[:sources_n]:
        group_kept, group_over = topics.cap(by_source[source], scores, posts_n)
        kept += group_kept
        over.update(group_over)
    for source in ordered[sources_n:]:
        over.update({post.id: "not in this rotation" for group in by_source[source] for post in group})
    return kept, over


def _attachment_key(attachment: dict) -> str:
    """What makes two attachments the same piece of media: the file they point at, or the card's address."""
    for key in ("path",):
        if attachment.get(key):
            return attachment[key]
    for nested in ("file", "poster", "image"):
        entry = attachment.get(nested)
        if isinstance(entry, dict) and entry.get("path"):
            return entry["path"]
    return attachment.get("url") or ""


def _merge_attachments(survivor: Post, dropped: Post) -> None:
    """A duplicate row's media moves onto the kept post; an attachment the survivor already has stays
    once, keyed by the file it names."""
    have = {_attachment_key(attachment) for attachment in survivor.attachments}
    for attachment in dropped.attachments:
        key = _attachment_key(attachment)
        if key and key not in have:
            survivor.attachments.append(attachment)
            have.add(key)


def _attachment_paths(post: Post) -> list[str]:
    """Every file an attachment names — image, video file and poster, card picture — as store paths."""
    paths = []
    for attachment in post.attachments:
        for entry in [attachment, *(attachment.get(key) for key in ("file", "poster", "image"))]:
            if isinstance(entry, dict) and entry.get("path"):
                paths.append(entry["path"])
    return paths


def _package(posts: list[Post], store: Store, subscriptions: dict, now: datetime) -> dict:
    last = store.last_build_at()
    start = last or min(datetime.fromisoformat(post.posted_at) for post in posts)
    return {
        "schema": 1,
        "id": f"digest-{now.astimezone(timezone.utc):%Y-%m-%dT%H-%M-%SZ}",
        "window": {"from": iso(start), "to": iso(now)},
        "folders": subscriptions["folders"],
        "sources": store.source_statuses(),
        "posts": [wire(post) for post in sorted(posts, key=lambda post: post.posted_at, reverse=True)],
    }


def _write(package: dict, posts: list[Post], store: Store, destination: Path) -> None:
    """The delivery goes through the same writer as an article's; the files already live in the store."""
    files: list[tuple[str, Path]] = []
    for post in posts:
        files += [(path, store.root / path) for path in _attachment_paths(post)]
        for comment in post.comments:
            avatar = comment.get("avatar")
            if avatar:
                files.append((avatar["path"], store.root / avatar["path"]))
    write_delivery_from(destination, package, files)


def _unshowable(post: Post) -> str | None:
    """Why the magazine would draw a card that opens nothing; `None` when it would draw a real one."""
    if not post.permalink:
        return "no permalink"
    if post.text or post.attachments or post.media_errors:
        return None
    return "neither text nor media"


def _attachment_showable(attachment: dict) -> bool:
    """Whether an attachment still has something to draw after missing files dropped out of it."""
    if attachment.get("kind") == "card":
        return bool(attachment.get("title") or attachment.get("description") or attachment.get("domain"))
    if attachment.get("kind") == "video":
        return bool((attachment.get("file") or {}).get("path") or (attachment.get("poster") or {}).get("path"))
    return bool(attachment.get("path"))


def _available(post: Post, store: Store) -> str | None:
    """Drops the files the store does not hold; a post left with nothing to draw is skipped like an empty one."""
    kept = []
    for attachment in post.attachments:
        for key in ("file", "poster", "image"):
            entry = attachment.get(key)
            if isinstance(entry, dict) and entry.get("path") and not (store.root / entry["path"]).exists():
                print(f"{post.id}: missing {entry['path']}")
                attachment[key] = None
        if isinstance(attachment.get("path"), str) and not (store.root / attachment["path"]).exists():
            print(f"{post.id}: missing {attachment['path']}")
            attachment["path"] = None
        if _attachment_showable(attachment):
            kept.append(attachment)
    post.attachments = kept
    if post.text or post.attachments or post.media_errors:
        return None
    return "missing media"


def _prune(folder: Path) -> None:
    deliveries = sorted(folder.glob("digest-*.tar"))
    for old in deliveries[:-KEEP]:
        old.unlink()
    for stale in folder.glob("*.incoming"):
        stale.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())

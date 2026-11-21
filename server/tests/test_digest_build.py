import json
import tarfile
import unittest
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

from digest import build
from digest.store import Store
from package import read_delivery
from tests.fakes import post
from tests.test_digest_store import png


class BuildTests(unittest.TestCase):
    def build(self, root: Path, reed: Path, *extra: str) -> int:
        subscriptions = Path(root).parent / "subscriptions.json"
        subscriptions.write_text(
            json.dumps({"folders": ["ml", "design", "tech"], "sources": []}),
            encoding="utf-8",
        )
        return build.main([
            "--root", str(root), "--folder", str(reed), "--subscriptions", str(subscriptions), "--force", *extra,
        ])

    def test_a_build_writes_one_delivery_with_every_new_post_and_its_picture(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            store = Store(root)
            first = post("x/1")
            first.attachments = [{"kind": "image", **store.save_media("x/1", 0, png(640, 480), "png")}]
            store.append([first, post("x/2")])
            store.save_source_statuses([
                {"id": "x/karpathy", "network": "x", "name": "Andrej Karpathy", "folders": ["ml"], "status": "ok", "detail": None},
                {"id": "telegram/durov", "network": "telegram", "name": "Pavel Durov", "folders": ["tech"], "status": "failed", "detail": "the login expired"},
            ])
            self.assertEqual(self.build(root, reed), 0)
            deliveries = list((reed / "digests").glob("digest-*.tar"))
            self.assertEqual(len(deliveries), 1)
            with tarfile.open(deliveries[0]) as archive:
                members = archive.getnames()
                self.assertEqual(members[0], "package.json")
                package = json.loads(archive.extractfile("package.json").read())
                self.assertIn("media/x-1-0.png", members)
            self.assertEqual(package["schema"], 1)
            self.assertEqual(package["folders"], ["ml", "design", "tech"])
            self.assertEqual([item["id"] for item in package["posts"]], ["x/1", "x/2"])
            self.assertEqual(package["sources"][1]["status"], "failed")
            self.assertEqual(package["sources"][1]["detail"], "the login expired")
            for item in package["posts"]:
                self.assertTrue(item["permalink"])
                self.assertTrue(item["text"] or item["attachments"])
            self.assertEqual(package["posts"][0]["attachments"][0]["width"], 640)
            self.assertTrue(package["posts"][0]["postedAt"].endswith("Z"))

    def test_a_video_file_rides_the_delivery_next_to_its_poster(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            store = Store(root)
            clip = post("x/1", text=None)
            clip.attachments = [{
                "kind": "video",
                "poster": store.save_media("x/1", "0-poster", png(640, 480), "png"),
                "file": store.save_file("x/1", "0-video", b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64, "mp4"),
            }]
            store.append([clip])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                members = opened.getnames()
                package = json.loads(opened.extractfile("package.json").read())
            self.assertIn("media/x-1-0-video.mp4", members)
            self.assertIn("media/x-1-0-poster.png", members)
            video = next(a for a in package["posts"][0]["attachments"] if a["kind"] == "video")
            self.assertEqual(video["file"]["path"], "media/x-1-0-video.mp4")

    def test_a_poster_that_is_the_first_picture_is_written_once(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            store = Store(root)
            clip = post("x/1", text=None)
            poster = store.save_media("x/1", 0, png(640, 480), "png")
            clip.attachments = [
                {"kind": "image", **poster},
                {
                    "kind": "video",
                    "poster": poster,
                    "file": store.save_file("x/1", "1-video", b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64, "mp4"),
                },
            ]
            store.append([clip])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                names = opened.getnames()
            self.assertEqual(names.count("media/x-1-0.png"), 1)
            self.assertIn("media/x-1-1-video.mp4", names)

    def test_the_digest_reads_through_the_article_delivery_reader(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            Store(root).append([post("x/1")])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            delivery = read_delivery(archive)
            self.assertEqual(delivery.package["schema"], 1)
            self.assertIn("posts", delivery.package)

    def test_a_second_build_with_nothing_new_writes_nothing(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            Store(root).append([post("x/1")])
            self.build(root, reed)
            self.assertEqual(self.build(root, reed), 0)
            self.assertEqual(len(list((reed / "digests").glob("digest-*.tar"))), 1)

    def test_a_post_the_magazine_could_not_show_is_skipped_and_the_next_build_runs(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            empty = post("x/1", text="")
            Store(root).append([empty])
            self.assertEqual(self.build(root, reed), 0)
            self.assertEqual(list((reed / "digests").glob("digest-*.tar")), [])
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "neither text nor media"})
            Store(root).append([post("x/2")])
            self.assertEqual(self.build(root, reed), 0)
            self.assertEqual(len(list((reed / "digests").glob("digest-*.tar"))), 1)

    def test_a_video_without_a_poster_is_skipped(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            video = post("x/1", text="")
            video.attachments = [{"kind": "video", "file": None, "poster": None}]
            Store(root).append([video])
            self.assertEqual(self.build(root, reed), 0)
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "missing media"})

    def test_a_missing_picture_is_dropped_and_the_text_stays(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            with_picture = post("x/1")
            with_picture.attachments = [{"kind": "image", "path": "media/missing.png", "width": 1, "height": 1}]
            Store(root).append([with_picture])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
                self.assertNotIn("media/missing.png", opened.getnames())
            self.assertEqual(package["posts"][0]["attachments"], [])

    def test_a_post_whose_only_picture_is_missing_is_skipped(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            with_picture = post("x/1", text="")
            with_picture.attachments = [{"kind": "image", "path": "media/missing.png", "width": 1, "height": 1}]
            Store(root).append([with_picture])
            self.build(root, reed)
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "missing media"})

    def test_the_build_reads_its_subscriptions_file(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            Store(root).append([post("x/1")])
            subscriptions = Path(folder) / "subs.json"
            subscriptions.write_text(json.dumps({"folders": ["alpha"], "sources": []}), encoding="utf-8")
            build.main([
                "--root", str(root), "--folder", str(reed), "--subscriptions", str(subscriptions), "--force",
            ])
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(package["folders"], ["alpha"])

    def test_the_settings_file_topics_relabel_the_posts_and_the_limit_drops_the_rest(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "networks": {"x": {"topics": ["small model", "nothing alike"]}},
                "limit": 1,
            }), encoding="utf-8")
            Store(root).append([post("x/1"), post("x/2")])
            from unittest import mock

            from digest.topics import lexical

            with mock.patch("digest.topics.default_scorer", return_value=lexical):
                self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(len(package["posts"]), 1)
            self.assertEqual(package["posts"][0]["folders"], ["small model"])
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/2": "over the digest limit"})

    def test_a_thread_shares_one_topic_and_the_limit_never_splits_it(self):
        from unittest import mock

        from digest.topics import lexical

        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "networks": {"x": {"topics": ["small model"]}},
                "limit": 2,
            }), encoding="utf-8")
            story = [
                post("x/0", text="small model alpha briefing one"),
                post("x/1", text="entirely different wording about the small model beta"),
                post("x/2", text="third entry own vocabulary mentions small model gamma"),
            ]
            for item in story:
                item.thread = "x/0"
            solo = post("x/9", text="small model solo note zeta eta theta")
            solo.posted_at = "2026-11-07T10:00:00Z"
            for item in story:
                item.posted_at = "2026-11-07T09:00:00Z"
            Store(root).append([*story, solo])
            with mock.patch("digest.topics.default_scorer", return_value=lexical):
                self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual([item["id"] for item in package["posts"]], ["x/9"])
            skipped = Store(root).builds()[-1]["skipped"]
            self.assertEqual(set(skipped), {"x/0", "x/1", "x/2"})
            self.assertTrue(all(reason == "over the digest limit" for reason in skipped.values()))

    def test_a_below_threshold_thread_drops_whole_and_an_above_one_keeps_its_textless_posts(self):
        from unittest import mock

        from digest.topics import lexical

        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "networks": {"x": {"topics": ["small model"]}},
            }), encoding="utf-8")
            store = Store(root)
            below_lead = post("x/0", text="I baked bread and fed the cat", folders=())
            below_lead.thread = "x/0"
            below_photo = post("x/1", text="", folders=())
            below_photo.thread = "x/0"
            below_photo.attachments = [{"kind": "image", **store.save_media("x/1", 0, png(640, 480), "png")}]
            above_lead = post("x/2", text="small model release notes", folders=())
            above_lead.thread = "x/2"
            above_photo = post("x/3", text="", folders=())
            above_photo.thread = "x/2"
            above_photo.attachments = [{"kind": "image", **store.save_media("x/3", 0, png(640, 480), "png")}]
            store.append([below_lead, below_photo, above_lead, above_photo])
            with mock.patch("digest.topics.default_scorer", return_value=lexical):
                self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual([item["id"] for item in package["posts"]], ["x/2", "x/3"])
            skipped = Store(root).builds()[-1]["skipped"]
            self.assertEqual(skipped, {"x/0": "below the topic threshold", "x/1": "below the topic threshold"})

    def test_the_limit_caps_each_source_not_the_whole_delivery(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({"limit": 1}), encoding="utf-8")
            other = replace(post("x/2"), source="x/elsewhere")
            Store(root).append([post("x/1"), other])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(len(package["posts"]), 2)
            self.assertEqual(Store(root).builds()[-1]["skipped"], {})

    def test_a_network_limit_caps_the_whole_network_not_each_source(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "networks": {"instagram": {"limit": 2}},
            }), encoding="utf-8")
            photos = [
                replace(
                    post(f"instagram/{handle}{index}"),
                    network="instagram", source=f"instagram/{handle}",
                    id=f"instagram/{handle}{index}", author={"handle": handle, "name": handle},
                    permalink=f"https://www.instagram.com/p/{handle}{index}/", folders=[],
                )
                for handle, count in (("a", 2), ("b", 1))
                for index in range(count)
            ]
            Store(root).append([*photos, post("x/1")])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            shipped = [item["id"] for item in package["posts"]]
            self.assertEqual(len([item for item in shipped if item.startswith("instagram/")]), 2)
            self.assertIn("x/1", shipped)
            self.assertEqual(len(Store(root).builds()[-1]["skipped"]), 1)

    def test_a_rotation_ships_only_the_longest_waiting_sources(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "rotation": {"sources": 1, "posts": 2},
            }), encoding="utf-8")
            posts = [
                replace(post(f"x/{source}/{index}"), source=f"x/{source}")
                for source in ("aaa", "bbb", "ccc")
                for index in range(3)
            ]
            Store(root).append(posts)
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            shipped = [item["id"] for item in package["posts"]]
            self.assertEqual(len(shipped), 2)
            self.assertEqual(len({item.rsplit("/", 2)[0] for item in shipped}), 1)
            skipped = Store(root).builds()[-1]["skipped"]
            self.assertEqual(len(skipped), 7)
            self.assertEqual(sum(1 for reason in skipped.values() if reason == "not in this rotation"), 6)

    def test_the_rotation_gives_each_network_its_own_slots(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "rotation": {"sources": 1, "posts": 2},
            }), encoding="utf-8")
            posts = [
                replace(post(f"x/{source}/{index}"), source=f"x/{source}")
                for source in ("aaa", "bbb")
                for index in range(3)
            ] + [
                replace(post(f"telegram/{source}/{index}"), network="telegram", source=f"telegram/{source}")
                for source in ("ccc", "ddd")
                for index in range(3)
            ]
            Store(root).append(posts)
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            shipped = [item["id"] for item in package["posts"]]
            self.assertEqual(len(shipped), 4)
            self.assertEqual(len({item.split("/")[0] for item in shipped}), 2)

    def test_a_post_below_the_topic_threshold_is_filtered_and_a_topicless_network_is_not(self):
        from unittest import mock

        from digest.topics import lexical

        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "networks": {"x": {"topics": ["small model"]}},
            }), encoding="utf-8")
            off_topic = replace(post("x/1", text="I baked bread and fed the cat"), folders=[])
            photos = replace(
                post("instagram/sea1", text="a day at the sea"),
                network="instagram", source="instagram/recommendations",
                id="instagram/sea1", author={"handle": "a", "name": "A"},
                permalink="https://www.instagram.com/p/sea1/", folders=[],
            )
            Store(root).append([off_topic, photos])
            with mock.patch("digest.topics.default_scorer", return_value=lexical):
                self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual([item["id"] for item in package["posts"]], ["instagram/sea1"])
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "below the topic threshold"})

    def test_without_topics_the_feed_is_capped_at_forty(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            Store(root).append([post(f"x/{index}") for index in range(45)])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(len(package["posts"]), build.FEED_LIMIT)
            self.assertEqual(len(Store(root).builds()[-1]["skipped"]), 45 - build.FEED_LIMIT)

    def test_a_disabled_digest_builds_nothing(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({"enabled": False}), encoding="utf-8")
            Store(root).append([post("x/1")])
            self.assertEqual(self.build(root, reed), 0)
            self.assertEqual(list((reed / "digests").glob("digest-*.tar")), [])

    def test_pruning_keeps_the_newest_deliveries(self):
        with TemporaryDirectory() as folder:
            reed = Path(folder)
            for hour in range(16):
                (reed / f"digest-2026-11-07T{hour:02d}-00-00Z.tar").write_bytes(b"")
            (reed / "notes.txt").write_text("kept")
            build._prune(reed)
            names = sorted(item.name for item in reed.glob("digest-*.tar"))
            self.assertEqual(len(names), build.KEEP)
            self.assertFalse((reed / "digest-2026-11-07T00-00-00Z.tar").exists())
            self.assertTrue((reed / "digest-2026-11-07T15-00-00Z.tar").exists())
            self.assertTrue((reed / "notes.txt").exists())


    def test_a_prolific_author_scores_lower_until_somebody_else_wins(self):
        from unittest import mock

        from digest.topics import lexical

        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "networks": {"x": {"topics": ["small model"]}},
                "limit": 2,
            }), encoding="utf-8")
            store = Store(root)
            loud_author = {"handle": "loud", "name": "Loud"}
            loud_a = replace(post("x/loud/new1"), source="x/loud", author=loud_author)
            loud_a.posted_at = "2026-11-07T10:00:00Z"
            loud_b = replace(post("x/loud/new2"), source="x/loud", author=loud_author)
            loud_b.posted_at = "2026-11-07T10:01:00Z"
            fresh = replace(post("x/fresh/new"), source="x/fresh", author={"handle": "fresh", "name": "Fresh"})
            fresh.posted_at = "2026-11-07T09:00:00Z"
            loud_c = replace(post("x/loud/new3"), source="x/loud", author=loud_author)
            loud_c.posted_at = "2026-11-07T09:30:00Z"
            store.append([loud_a, loud_b, loud_c, fresh])
            with mock.patch("digest.topics.default_scorer", return_value=lexical):
                self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            shipped = {item["id"] for item in package["posts"]}
            self.assertEqual(shipped, {"x/fresh/new", "x/loud/new2"})
            skipped = Store(root).builds()[-1]["skipped"]
            self.assertEqual(set(skipped), {"x/loud/new1", "x/loud/new3"})

    def telegram_post(self, post_id, text, attachments=()):
        return replace(
            post(post_id, text=text),
            network="telegram", source="telegram/news", id=post_id,
            author={"handle": "news", "name": "News"},
            permalink=f"https://t.me/news/{post_id.rsplit('/', 1)[-1]}",
            attachments=list(attachments), folders=[],
        )

    def test_a_cut_caption_pair_ships_only_the_whole_text_and_keeps_the_media(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            whole = " ".join(f"слово номер {index} в длинном тексте поста" for index in range(60))
            cut = whole[:250] + "…"
            store = Store(root)
            (root / "media").mkdir(parents=True)
            (root / "media" / "news-2-0.jpg").write_bytes(png())
            store.append([
                self.telegram_post("telegram/news/1", whole),
                self.telegram_post(
                    "telegram/news/2", cut,
                    attachments=[{"kind": "image", "path": "media/news-2-0.jpg", "width": 4, "height": 3}],
                ),
            ])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            shipped = package["posts"]
            self.assertEqual([item["id"] for item in shipped], ["telegram/news/1"])
            self.assertIn("media/news-2-0.jpg", [a["path"] for a in shipped[0]["attachments"]])
            self.assertEqual(Store(root).builds()[-1]["skipped"]["telegram/news/2"], "a shorter copy of the same text")

    def test_a_source_limit_caps_one_source_not_the_delivery(self):
        with TemporaryDirectory() as folder:
            root, reed = Path(folder) / "data", Path(folder) / "reed"
            reed.mkdir(parents=True)
            (reed / "digest-settings.json").write_text(json.dumps({
                "limit": 40,
                "sources": {"x/teortaxestex": {"limit": 1}},
            }), encoding="utf-8")
            loud = [replace(post(f"x/teortaxestex/{index}"), source="x/teortaxestex") for index in range(3)]
            quiet = replace(post("x/other/9"), source="x/other")
            Store(root).append([*loud, quiet])
            self.build(root, reed)
            archive = next((reed / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            shipped = [item["id"] for item in package["posts"]]
            self.assertEqual(len([item for item in shipped if item.startswith("x/teortaxestex/")]), 1)
            self.assertIn("x/other/9", shipped)




class ScheduleTests(unittest.TestCase):
    def test_the_next_build_is_the_first_scheduled_time_after_the_last(self):
        morning = datetime(2026, 11, 7, 7, 0).astimezone()
        self.assertEqual(build.next_build_time(morning).hour, 8)
        evening = datetime(2026, 11, 7, 9, 0).astimezone()
        self.assertEqual(build.next_build_time(evening).hour, 20)
        night = datetime(2026, 11, 7, 21, 0).astimezone()
        self.assertEqual(build.next_build_time(night).day, 8)
        self.assertEqual(build.next_build_time(night).hour, 8)

    def test_a_store_with_no_build_is_due(self):
        with TemporaryDirectory() as folder:
            self.assertTrue(build.due(Store(Path(folder)), datetime.now(timezone.utc)))

    def test_a_store_built_this_evening_is_not_due_again_tonight(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            store.record_build({"id": "digest-1", "at": (datetime.now(timezone.utc) + timedelta(minutes=1)).isoformat(), "post_ids": []})
            self.assertFalse(build.due(store, datetime.now(timezone.utc)))

if __name__ == "__main__":
    unittest.main()

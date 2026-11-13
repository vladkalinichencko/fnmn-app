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
    def build(self, root: Path, fnmn: Path, *extra: str) -> int:
        subscriptions = Path(root).parent / "subscriptions.json"
        subscriptions.write_text(
            json.dumps({"folders": ["ml", "design", "tech"], "sources": []}),
            encoding="utf-8",
        )
        return build.main([
            "--root", str(root), "--folder", str(fnmn), "--subscriptions", str(subscriptions), "--force", *extra,
        ])

    def test_a_build_writes_one_delivery_with_every_new_post_and_its_picture(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            store = Store(root)
            first = post("x/1")
            first.media = [store.save_media("x/1", 0, png(640, 480), "png")]
            store.append([first, post("x/2")])
            store.save_source_statuses([
                {"id": "x/karpathy", "network": "x", "name": "Andrej Karpathy", "folders": ["ml"], "status": "ok", "detail": None},
                {"id": "telegram/durov", "network": "telegram", "name": "Pavel Durov", "folders": ["tech"], "status": "failed", "detail": "the login expired"},
            ])
            self.assertEqual(self.build(root, fnmn), 0)
            deliveries = list((fnmn / "digests").glob("digest-*.tar"))
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
                self.assertTrue(item["text"] or item["media"] or item["video"])
            self.assertEqual(package["posts"][0]["media"][0]["width"], 640)
            self.assertTrue(package["posts"][0]["postedAt"].endswith("Z"))

    def test_a_video_file_rides_the_delivery_next_to_its_poster(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            store = Store(root)
            clip = post("x/1", text=None)
            clip.video = {
                "poster": store.save_media("x/1", "poster", png(640, 480), "png"),
                "file": store.save_file("x/1", "video", b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64, "mp4"),
            }
            store.append([clip])
            self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                members = opened.getnames()
                package = json.loads(opened.extractfile("package.json").read())
            self.assertIn("media/x-1-video.mp4", members)
            self.assertIn("media/x-1-poster.png", members)
            self.assertEqual(package["posts"][0]["video"]["file"]["path"], "media/x-1-video.mp4")

    def test_the_digest_reads_through_the_article_delivery_reader(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            Store(root).append([post("x/1")])
            self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            delivery = read_delivery(archive)
            self.assertEqual(delivery.package["schema"], 1)
            self.assertIn("posts", delivery.package)

    def test_a_second_build_with_nothing_new_writes_nothing(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            Store(root).append([post("x/1")])
            self.build(root, fnmn)
            self.assertEqual(self.build(root, fnmn), 0)
            self.assertEqual(len(list((fnmn / "digests").glob("digest-*.tar"))), 1)

    def test_a_post_the_magazine_could_not_show_is_skipped_and_the_next_build_runs(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            empty = post("x/1", text="")
            Store(root).append([empty])
            self.assertEqual(self.build(root, fnmn), 0)
            self.assertEqual(list((fnmn / "digests").glob("digest-*.tar")), [])
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "neither text nor media"})
            Store(root).append([post("x/2")])
            self.assertEqual(self.build(root, fnmn), 0)
            self.assertEqual(len(list((fnmn / "digests").glob("digest-*.tar"))), 1)

    def test_a_video_without_a_poster_is_skipped(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            video = post("x/1", text="")
            video.video = {"poster": None}
            Store(root).append([video])
            self.assertEqual(self.build(root, fnmn), 0)
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "a video with no poster"})

    def test_a_missing_picture_is_dropped_and_the_text_stays(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            with_picture = post("x/1")
            with_picture.media = [{"path": "media/missing.png", "width": 1, "height": 1}]
            Store(root).append([with_picture])
            self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
                self.assertNotIn("media/missing.png", opened.getnames())
            self.assertEqual(package["posts"][0]["media"], [])

    def test_a_post_whose_only_picture_is_missing_is_skipped(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            with_picture = post("x/1", text="")
            with_picture.media = [{"path": "media/missing.png", "width": 1, "height": 1}]
            Store(root).append([with_picture])
            self.build(root, fnmn)
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "missing media"})

    def test_the_build_reads_its_subscriptions_file(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            Store(root).append([post("x/1")])
            subscriptions = Path(folder) / "subs.json"
            subscriptions.write_text(json.dumps({"folders": ["alpha"], "sources": []}), encoding="utf-8")
            build.main([
                "--root", str(root), "--folder", str(fnmn), "--subscriptions", str(subscriptions), "--force",
            ])
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(package["folders"], ["alpha"])

    def test_the_settings_file_topics_relabel_the_posts_and_the_limit_drops_the_rest(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            fnmn.mkdir(parents=True)
            (fnmn / "digest-settings.json").write_text(json.dumps({
                "networks": {"x": {"topics": ["small model", "nothing alike"]}},
                "limit": 1,
            }), encoding="utf-8")
            Store(root).append([post("x/1"), post("x/2")])
            from unittest import mock

            from digest.topics import lexical

            with mock.patch("digest.topics.default_scorer", return_value=lexical):
                self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(len(package["posts"]), 1)
            self.assertEqual(package["posts"][0]["folders"], ["small model"])
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/2": "over the digest limit"})

    def test_a_thread_shares_one_topic_and_the_limit_never_splits_it(self):
        from unittest import mock

        from digest.topics import lexical

        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            fnmn.mkdir(parents=True)
            (fnmn / "digest-settings.json").write_text(json.dumps({
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
                self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual([item["id"] for item in package["posts"]], ["x/9"])
            skipped = Store(root).builds()[-1]["skipped"]
            self.assertEqual(set(skipped), {"x/0", "x/1", "x/2"})
            self.assertTrue(all(reason == "over the digest limit" for reason in skipped.values()))

    def test_the_limit_caps_each_source_not_the_whole_delivery(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            fnmn.mkdir(parents=True)
            (fnmn / "digest-settings.json").write_text(json.dumps({"limit": 1}), encoding="utf-8")
            other = replace(post("x/2"), source="x/elsewhere")
            Store(root).append([post("x/1"), other])
            self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(len(package["posts"]), 2)
            self.assertEqual(Store(root).builds()[-1]["skipped"], {})

    def test_a_post_below_the_topic_threshold_is_filtered_and_a_topicless_network_is_not(self):
        from unittest import mock

        from digest.topics import lexical

        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            fnmn.mkdir(parents=True)
            (fnmn / "digest-settings.json").write_text(json.dumps({
                "networks": {"x": {"topics": ["small model"]}},
            }), encoding="utf-8")
            off_topic = replace(post("x/1", text="I baked bread and fed the cat"), folders=[])
            photos = replace(
                post("instagram/a/1", text="a day at the sea"),
                network="instagram", source="instagram/recommendations",
                id="instagram/a/1", author={"handle": "a", "name": "A"},
                permalink="https://www.instagram.com/p/1/", folders=[],
            )
            Store(root).append([off_topic, photos])
            with mock.patch("digest.topics.default_scorer", return_value=lexical):
                self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual([item["id"] for item in package["posts"]], ["instagram/a/1"])
            self.assertEqual(Store(root).builds()[-1]["skipped"], {"x/1": "below the topic threshold"})

    def test_without_topics_the_feed_is_capped_at_forty(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            fnmn.mkdir(parents=True)
            Store(root).append([post(f"x/{index}") for index in range(45)])
            self.build(root, fnmn)
            archive = next((fnmn / "digests").glob("digest-*.tar"))
            with tarfile.open(archive) as opened:
                package = json.loads(opened.extractfile("package.json").read())
            self.assertEqual(len(package["posts"]), build.FEED_LIMIT)
            self.assertEqual(len(Store(root).builds()[-1]["skipped"]), 45 - build.FEED_LIMIT)

    def test_a_disabled_digest_builds_nothing(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            fnmn.mkdir(parents=True)
            (fnmn / "digest-settings.json").write_text(json.dumps({"enabled": False}), encoding="utf-8")
            Store(root).append([post("x/1")])
            self.assertEqual(self.build(root, fnmn), 0)
            self.assertEqual(list((fnmn / "digests").glob("digest-*.tar")), [])

    def test_pruning_keeps_the_newest_deliveries(self):
        with TemporaryDirectory() as folder:
            fnmn = Path(folder)
            for hour in range(16):
                (fnmn / f"digest-2026-11-07T{hour:02d}-00-00Z.tar").write_bytes(b"")
            (fnmn / "notes.txt").write_text("kept")
            build._prune(fnmn)
            names = sorted(item.name for item in fnmn.glob("digest-*.tar"))
            self.assertEqual(len(names), build.KEEP)
            self.assertFalse((fnmn / "digest-2026-11-07T00-00-00Z.tar").exists())
            self.assertTrue((fnmn / "digest-2026-11-07T15-00-00Z.tar").exists())
            self.assertTrue((fnmn / "notes.txt").exists())


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

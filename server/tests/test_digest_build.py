import json
import tarfile
import unittest
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
            video.video = {"poster": None, "duration": 42}
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

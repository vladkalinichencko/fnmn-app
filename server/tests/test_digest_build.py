import json
import tarfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

from digest import build, train
from digest.store import Post, Store
from tests.test_digest_store import png


def post(post_id: str, text: str = "A small model that reads the whole catalog.", folders=("ml",)) -> Post:
    return Post(
        id=post_id,
        network="x",
        source="x/karpathy",
        author={"handle": "karpathy", "name": "Andrej Karpathy"},
        permalink=f"https://x.com/karpathy/status/{post_id.split('/')[-1]}",
        posted_at="2026-11-07T09:30:00Z",
        text=text,
        folders=list(folders),
    )


class BuildTests(unittest.TestCase):
    def build(self, root: Path, fnmn: Path, *extra: str) -> int:
        return build.main(["--root", str(root), "--folder", str(fnmn), "--force", *extra])

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

    def test_a_second_build_with_nothing_new_writes_nothing(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            Store(root).append([post("x/1")])
            self.build(root, fnmn)
            self.assertEqual(self.build(root, fnmn), 0)
            self.assertEqual(len(list((fnmn / "digests").glob("digest-*.tar"))), 1)

    def test_a_post_the_magazine_could_not_show_stops_the_build(self):
        with TemporaryDirectory() as folder:
            root, fnmn = Path(folder) / "data", Path(folder) / "fnmn"
            empty = post("x/1", text="")
            Store(root).append([empty])
            with self.assertRaises(ValueError):
                self.build(root, fnmn)
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


class TrainRowsTests(unittest.TestCase):
    def test_engagement_weights_the_rows_and_hides_the_hidden(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            store.append([
                post("x/1", text="hidden one"),
                post("x/2", text="saved one"),
                post("x/3", text="opened one"),
                post("x/4", text="plain one"),
            ])
            events = [
                {"kind": "hidden", "postID": "x/1"},
                {"kind": "saved", "postID": "x/2"},
                {"kind": "opened", "postID": "x/3"},
            ]
            texts, labels = train.rows(store, events)
            self.assertNotIn("hidden one", texts)
            self.assertEqual(texts.count("saved one"), 3)
            self.assertEqual(texts.count("opened one"), 2)
            self.assertEqual(texts.count("plain one"), 1)
            self.assertEqual(set(labels), {"ml"})

    def test_a_journal_of_engagement_reads_across_devices(self):
        with TemporaryDirectory() as folder:
            fnmn = Path(folder)
            state = fnmn / "digest-state"
            state.mkdir()
            (state / "phone.jsonl").write_text('{"kind": "opened", "postID": "x/1"}\n')
            (state / "tablet.jsonl").write_text('{"kind": "saved", "postID": "x/2"}\nbroken\n')
            events = train.engagement(fnmn)
            self.assertEqual(len(events), 2)


if __name__ == "__main__":
    unittest.main()

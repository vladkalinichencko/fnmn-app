import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from digest.store import Post, Store, image_size, iso, safe


def png(width: int = 4, height: int = 3) -> bytes:
    """A PNG header with the given size, enough for the store to measure it."""
    header = b"\x89PNG\r\n\x1a\n" + (13).to_bytes(4, "big") + b"IHDR"
    return header + width.to_bytes(4, "big") + height.to_bytes(4, "big") + b"\x08\x06\x00\x00\x00"


def jpeg(width: int = 7, height: int = 5) -> bytes:
    """An SOI, an APP0 of the usual length, and an SOF0 that carries the size."""
    app0 = b"\xff\xe0" + (16).to_bytes(2, "big") + b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    sof0 = b"\xff\xc0" + (17).to_bytes(2, "big") + b"\x08" + height.to_bytes(2, "big") + width.to_bytes(2, "big") + b"\x03\x01\x11\x00\x02\x11\x01\x03\x11\x01"
    return b"\xff\xd8" + app0 + sof0 + b"\xff\xd9"


def post(post_id: str = "x/1") -> Post:
    return Post(
        id=post_id,
        network="x",
        source="x/karpathy",
        author={"handle": "karpathy", "name": "Andrej Karpathy"},
        permalink=f"https://x.com/karpathy/status/{post_id.split('/')[-1]}",
        posted_at="2026-11-07T09:30:00Z",
        text="A small model that reads the whole catalog.",
        folders=["ml"],
    )


class StoreTests(unittest.TestCase):
    def test_appending_the_same_post_twice_keeps_one(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            self.assertEqual(store.append([post()]), 1)
            self.assertEqual(store.append([post()]), 0)
            self.assertEqual(len(store.posts()), 1)

    def test_a_torn_last_line_is_skipped_and_the_next_run_appends(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            store.append([post()])
            with store.posts_file.open("a", encoding="utf-8") as log:
                log.write('{"id": "x/2", "network": "x"')
            self.assertEqual([item.id for item in store.posts()], ["x/1"])
            self.assertEqual(store.append([post("x/2")]), 1)

    def test_media_is_measured_before_it_is_stored(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            saved = store.save_media("x/1", 0, png(640, 480), "png")
            self.assertEqual(saved, {"path": "media/x-1-0.png", "width": 640, "height": 480})
            self.assertTrue((store.root / saved["path"]).exists())
            self.assertIsNone(store.save_media("x/1", 1, b"not a picture", "jpg"))

    def test_image_size_reads_png_jpeg_and_gif(self):
        self.assertEqual(image_size(png(640, 480)), (640, 480))
        self.assertEqual(image_size(jpeg(1200, 675)), (1200, 675))
        self.assertEqual(image_size(b"GIF89a" + (33).to_bytes(2, "little") + (44).to_bytes(2, "little") + b"\x00" * 8), (33, 44))
        self.assertIsNone(image_size(b""))

    def test_built_posts_leave_the_unconsumed_list(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            store.append([post("x/1"), post("x/2")])
            store.record_build({"id": "digest-1", "at": iso(__import__("datetime").datetime.now(__import__("datetime").timezone.utc)), "post_ids": ["x/1"]})
            self.assertEqual([item.id for item in store.unconsumed()], ["x/2"])

    def test_safe_names_keep_the_store_on_one_level(self):
        self.assertEqual(safe("x/1587-0"), "x-1587-0")
        self.assertNotIn("/", safe("../x/1"))


if __name__ == "__main__":
    unittest.main()

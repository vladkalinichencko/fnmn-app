import base64
import hashlib
import json
import tarfile
import tempfile
import unittest
from pathlib import Path

from package import Delivery, delivery_name, read_delivery, stable_id, write_delivery
from collect.prepare_browser_library import repackage
from collect.publish_books import publish


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)

    def test_archive_starts_with_the_package_and_keeps_every_file(self):
        delivery = Delivery({"material": {"title": "Ё"}}, {"assets/a.png": b"png", "assets/empty.txt": b"", "b.bin": b"x" * 512})
        path = self.folder / "a.tar"
        write_delivery(path, delivery)
        with tarfile.open(path) as archive:
            self.assertEqual(archive.getnames()[0], "package.json")
        header = path.read_bytes()[:512]
        self.assertEqual((header[156:157], header[257:265]), (b"0", b"ustar\x0000"))
        self.assertEqual(read_delivery(path), delivery)
        self.assertFalse(path.with_suffix(".incoming").exists())

    def test_an_unchanged_delivery_is_not_written_again(self):
        path = self.folder / "a.tar"
        delivery = Delivery({"material": {"title": "A"}}, {"assets/a.png": b"png"})
        write_delivery(path, delivery)
        written = path.stat().st_mtime_ns
        write_delivery(path, delivery)
        self.assertEqual(path.stat().st_mtime_ns, written)
        write_delivery(path, Delivery({"material": {"title": "B"}}))
        self.assertEqual(read_delivery(path).package["material"]["title"], "B")
        self.assertEqual([file.name for file in self.folder.iterdir()], ["a.tar"])

    def test_an_exported_book_becomes_a_delivery_with_its_pdf_beside_it(self):
        book = self.folder / "book"
        (book / "assets").mkdir(parents=True)
        (book / "assets" / "p.png").write_bytes(b"png")
        (book / "content.md").write_text("# One\n\nText ![p](assets/p.png)")
        (book / "metadata.json").write_text(json.dumps({
            "title": "Notes", "authors": ["Ada", "Bob"], "source_name": "notes one.pdf",
            "content_file": "content.md", "assets_directory": "assets", "toc": [],
        }))
        pdfs = self.folder / "pdfs"
        pdfs.mkdir()
        (pdfs / "notes one.pdf").write_bytes(b"%PDF")
        publish([book], self.folder / "FNMN", pdfs)
        stem = hashlib.sha256(b"book:notes one.pdf").hexdigest()
        delivery = read_delivery(self.folder / "FNMN" / "deliveries" / f"{stem}.tar")
        self.assertEqual(delivery.package["material"]["kind"], "book")
        self.assertNotIn("sourceURL", delivery.package["material"])
        self.assertEqual(delivery.package["material"]["byline"], "Ada, Bob")
        self.assertEqual(delivery.files, {"assets/p.png": b"png"})
        self.assertEqual((self.folder / "FNMN" / "originals" / f"{stem}.pdf").read_bytes(), b"%PDF")

    def test_repackage_turns_an_old_json_delivery_into_an_archive(self):
        url = "https://example.com/a"
        deliveries = self.folder / "deliveries"
        deliveries.mkdir()
        old = deliveries / (hashlib.sha256(url.encode()).hexdigest() + ".json")
        body = "# A\n\nText ![p](assets/p.png)"
        old.write_text(json.dumps({
            "material": {"title": "A", "sourceURL": url},
            "folders": [],
            "body": body,
            "files": {"assets/p.png": base64.b64encode(b"png").decode()},
        }))
        self.assertEqual(repackage([{"url": url, "title": "Other", "folders": ["Web"]}], self.folder), 1)
        self.assertFalse(old.exists())
        prepared = deliveries / delivery_name(stable_id("article", url))
        delivery = read_delivery(prepared)
        self.assertEqual(delivery.files, {"assets/p.png": b"png"})
        self.assertEqual(delivery.package["folders"], ["Web"])
        self.assertNotIn("files", delivery.package)


if __name__ == "__main__":
    unittest.main()

import base64
import hashlib
import json
import tarfile
import tempfile
import unittest
from pathlib import Path

from package import Delivery, read_delivery, write_delivery
from collect.prepare_browser_library import repackage


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
        delivery = read_delivery(old.with_suffix(".tar"))
        self.assertEqual(delivery.files, {"assets/p.png": b"png"})
        self.assertEqual(delivery.package["folders"], ["Web"])
        self.assertNotIn("files", delivery.package)


if __name__ == "__main__":
    unittest.main()

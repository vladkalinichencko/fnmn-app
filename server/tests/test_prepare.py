import hashlib
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from collect.prepare_browser_library import link_unprepared
from package import delivery_name, link_delivery, read_delivery, write_delivery


def row(url: str = "https://example.com/a") -> dict:
    return {"url": url, "title": "A", "folders": [], "sources": []}


class LinkNamingTests(unittest.TestCase):
    def test_a_new_link_is_named_by_its_material_id(self):
        with TemporaryDirectory() as folder:
            output = Path(folder)
            self.assertEqual(link_unprepared([row()], output), 1)
            path = output / "deliveries" / delivery_name("link:https://example.com/a")
            self.assertTrue(path.exists())
            self.assertEqual(read_delivery(path).package["material"]["id"], "link:https://example.com/a")

    def test_a_delivery_named_by_the_old_url_rule_is_renamed_not_rewritten(self):
        with TemporaryDirectory() as folder:
            output = Path(folder)
            deliveries = output / "deliveries"
            deliveries.mkdir(parents=True)
            legacy = deliveries / (hashlib.sha256(b"https://example.com/a").hexdigest() + ".tar")
            write_delivery(legacy, link_delivery("https://example.com/a", "A", []))
            self.assertEqual(link_unprepared([row()], output), 0)
            self.assertFalse(legacy.exists())
            self.assertTrue((deliveries / delivery_name("link:https://example.com/a")).exists())

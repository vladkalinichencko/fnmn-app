import hashlib
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from collect.prepare_browser_library import link_unprepared, prepare
from package import Delivery, delivery_name, link_delivery, read_delivery, stable_id, write_delivery


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


class PrepareFailureTests(unittest.TestCase):
    def test_a_failed_fetch_leaves_a_link_delivery(self):
        with TemporaryDirectory() as folder:
            output = Path(folder)
            with patch("collect.prepare_browser_library.import_link", side_effect=RuntimeError("down")):
                url, error = prepare(row(), output)
            self.assertEqual(url, "https://example.com/a")
            self.assertIsNotNone(error)
            path = output / "deliveries" / delivery_name("link:https://example.com/a")
            self.assertTrue(path.exists())
            material = read_delivery(path).package["material"]
            self.assertEqual(material["kind"], "link")
            self.assertEqual(material["title"], "A")

    def test_a_failed_refetch_keeps_the_delivery_and_writes_no_link(self):
        with TemporaryDirectory() as folder:
            output = Path(folder)
            deliveries = output / "deliveries"
            deliveries.mkdir(parents=True)
            article = deliveries / delivery_name(stable_id("article", "https://example.com/a"))
            write_delivery(article, Delivery({
                "version": 1,
                "material": {"id": "article:abc", "kind": "article", "title": "A", "sourceURL": "https://example.com/a"},
                "sections": [], "blocks": [], "folders": [], "body": "the prepared text",
            }))
            with patch("collect.prepare_browser_library.import_link", side_effect=RuntimeError("down")):
                _, error = prepare(row(), output, refetch=True)
            self.assertIsNotNone(error)
            self.assertTrue(article.exists())
            self.assertFalse((deliveries / delivery_name("link:https://example.com/a")).exists())

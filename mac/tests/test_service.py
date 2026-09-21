import json
import unittest
from pathlib import Path

from fnmn_service import prepare_article


class ArticleTests(unittest.TestCase):
    def test_fixture_preserves_structure_math_image_and_exact_url_identity(self):
        source = Path(__file__).with_name("fixture.html").read_text()
        package = prepare_article("https://example.com/article?edition=1", source, ["Inbox"])
        kinds = [block["kind"] for block in package["blocks"]]
        self.assertEqual(package["material"]["sourceURL"], "https://example.com/article?edition=1")
        self.assertEqual([section["title"] for section in package["sections"]], ["Fixture article", "Proof"])
        self.assertEqual(kinds.count("formula"), 1)
        self.assertEqual(json.dumps(package).count("<mi>x</mi>"), 1)
        self.assertIn("image", kinds)
        self.assertIn("https://example.com/figure.png", json.dumps(package))


if __name__ == "__main__":
    unittest.main()

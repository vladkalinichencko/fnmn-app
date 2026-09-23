import unittest
from pathlib import Path

from fnmn_service import ImportFailure, import_web_article


class ArticleTests(unittest.TestCase):
    def test_fixture_preserves_structure_math_image_and_exact_url_identity(self):
        source = Path(__file__).with_name("fixture.html").read_text()
        package = import_web_article(
            "https://example.com/article?edition=1",
            lambda url: source,
            lambda url: b"",
            ["Inbox"],
        )
        self.assertEqual(package["material"]["sourceURL"], "https://example.com/article?edition=1")
        self.assertEqual(package["material"]["title"], "Fixture article")
        self.assertEqual(package["sections"], [])
        self.assertEqual(package["blocks"], [])
        self.assertIn("# Fixture article", package["body"])
        self.assertIn("## Proof", package["body"])
        self.assertIn("x=2", package["body"])
        self.assertIn("y=3", package["body"])
        self.assertIn("![A figure](assets/", package["body"])
        self.assertTrue(any(path.endswith(".png") for path in package["files"]))

    def test_import_downloads_picture_files_and_leaves_the_figure_on_the_live_page(self):
        source = """
        <html><head><script src="https://cdn.example/app.js"></script></head>
        <body><article>
          <h1>Notes</h1>
          <p><img alt="slope" src="pic.png"></p>
          <figure id="chart"><div id="plot"></div><script>draw()</script></figure>
        </article></body></html>
        """
        seen = []

        def fetch_text(url):
            seen.append(("text", url))
            if url != "https://example.com/notes":
                raise OSError(url)
            return source

        def fetch_bytes(url):
            seen.append(("bytes", url))
            if url != "https://example.com/pic.png":
                raise OSError(url)
            return b"png"

        package = import_web_article("https://example.com/notes", fetch_text, fetch_bytes, ["Web"])
        self.assertEqual(package["material"]["title"], "Notes")
        self.assertIn("```fnmn-interactive\nhttps://example.com/notes\n#chart\n```", package["body"])
        self.assertNotIn("draw()", package["body"])
        path, encoded = next(iter(package["files"].items()))
        self.assertEqual(len(package["files"]), 1)
        self.assertTrue(path.startswith("assets/") and path.endswith(".png"))
        self.assertEqual(encoded, "cG5n")
        self.assertIn(f"]({path})", package["body"])
        self.assertEqual(seen, [("text", "https://example.com/notes"), ("bytes", "https://example.com/pic.png")])

    def test_missing_picture_fails_during_asset_fetch_and_returns_nothing(self):
        source = "<html><body><article><p>Hi</p><img src='pic.png'></article></body></html>"

        def fetch_bytes(url):
            raise OSError("missing")

        with self.assertRaises(ImportFailure) as caught:
            import_web_article("https://example.com/notes", lambda url: source, fetch_bytes, [])
        self.assertEqual(caught.exception.phase, "fetchingAssets")

    def test_heading_with_math_stays_one_section(self):
        source = """
        <html><body><article>
          <h2>The <script type="math/tex">\\sigma</script>-algebra</h2>
          <p>Next paragraph.</p>
        </article></body></html>
        """
        package = import_web_article("https://example.com/sigma", lambda url: source, lambda url: b"", [])
        self.assertIn("## The $\\sigma$-algebra", package["body"])
        self.assertEqual(package["sections"], [])

    def test_unread_page_fails_during_page_fetch(self):
        def fetch_text(url):
            raise OSError("down")

        with self.assertRaises(ImportFailure) as caught:
            import_web_article("https://example.com/notes", fetch_text, lambda url: b"", [])
        self.assertEqual(caught.exception.phase, "fetchingPage")


if __name__ == "__main__":
    unittest.main()

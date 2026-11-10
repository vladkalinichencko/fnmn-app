import unittest
from pathlib import Path

from adapters import article
from package import ImportFailure, package
from tests import fakes
from web import with_base


def imported_article(url, text, bytes, folders, rendered=None):
    """The package the app decodes, with its files under `files` as bytes, as a test reads it."""
    delivery = package(url, article.read(url, fakes.web(text, bytes, rendered), lambda *_: None), folders)
    return {**delivery.package, "files": delivery.files}


class ArticleTests(unittest.TestCase):
    def test_fixture_preserves_structure_math_image_and_exact_url_identity(self):
        source = Path(__file__).with_name("fixture.html").read_text()
        package = imported_article(
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

    def test_the_material_names_its_publisher_from_the_section_and_the_sites_own_name(self):
        page = """
        <html><head><meta property="og:site_name" content="Alex L. Zhang"></head>
        <body><article><h1>Shape</h1><p>Some prose about language models.</p></article></body></html>
        """

        def fetch_text(url):
            if url not in {"https://example.github.io/blog/2026/shape/", "https://example.github.io/blog/"}:
                raise OSError(url)
            return page

        package = imported_article("https://example.github.io/blog/2026/shape/", fetch_text, lambda url: b"", [])
        self.assertEqual(
            package["material"]["source"],
            {"homepage": "https://example.github.io/blog/", "name": "Alex L. Zhang"},
        )

    def test_an_error_page_is_refused_not_packaged(self):
        page = "<html><head><title>404 Not Found</title></head><body><p>The requested URL was not found on this server.</p></body></html>"
        with self.assertRaises(ImportFailure):
            article.read("https://example.com/dead", fakes.web(lambda url: page, lambda url: b""), lambda *_: None)
        self.assertIsNone(article.title("https://example.com/dead", fakes.web(lambda url: page)))

    def test_a_long_article_named_after_an_error_code_is_not_an_error_page(self):
        page = "<html><head><title>404: a history of the error page</title></head><body><article><p>" + " prose" * 200 + "</p></article></body></html>"
        package = imported_article("https://example.com/history", lambda url: page, lambda url: b"", [])
        self.assertEqual(package["material"]["title"], "404: a history of the error page")

    def test_a_page_that_is_only_a_frame_is_the_page_inside_it(self):
        shell = """
        <html><head><title>A Space</title></head><body>
          <iframe src="https://stripe.example/m.html" aria-hidden="true" style="display:none"></iframe>
          <iframe src="https://www.youtube.com/embed/abc"></iframe>
          <iframe class="space-iframe" src="https://owner-name.hf.space/?__theme=system"></iframe>
        </body></html>
        """
        inside = """
        <html><head><title>Counting</title></head><body><article>
          <h1>Counting</h1><p>Models track line breaks, and we ask where that signal lives.</p>
          <div id="plot"></div><script>draw()</script>
        </article></body></html>
        """
        seen = []

        def fetch_text(url):
            seen.append(url)
            return {"https://huggingface.co/spaces/owner/name": shell, "https://owner-name.hf.space/?__theme=system": inside}[url]

        package = imported_article("https://huggingface.co/spaces/owner/name", fetch_text, lambda url: b"", [])
        self.assertEqual(package["material"]["sourceURL"], "https://huggingface.co/spaces/owner/name")
        self.assertEqual(package["material"]["title"], "Counting")
        self.assertIn("Models track line breaks", package["body"])
        self.assertIn("```fnmn-interactive\nhttps://owner-name.hf.space/?__theme=system\n#plot\n```", package["body"])
        self.assertEqual(package["material"]["source"], {"homepage": "https://huggingface.co/owner", "name": "owner"})
        self.assertNotIn("https://stripe.example/m.html", seen)

    def test_a_page_with_prose_is_not_replaced_by_its_frames(self):
        page = '<html><body><article><h1>T</h1><p>Plenty of prose here, with commas, to count as text.</p><iframe src="https://other.example/x"></iframe></article></body></html>'
        seen = []

        def fetch_text(url):
            seen.append(url)
            return page

        package = imported_article("https://example.com/a", fetch_text, lambda url: b"", [])
        self.assertIn("Plenty of prose", package["body"])
        self.assertNotIn("https://other.example/x", seen)

    def test_a_frame_that_cannot_be_read_leaves_the_page_as_it_was(self):
        shell = '<html><head><title>Shell</title></head><body><iframe src="https://gone.example/"></iframe></body></html>'

        def fetch_text(url):
            if url == "https://example.com/shell":
                return shell
            raise OSError(url)

        def browser(url):
            if url == "https://example.com/shell":
                return shell
            raise OSError("no browser")

        package = imported_article("https://example.com/shell", fetch_text, lambda url: b"", [], rendered=browser)
        self.assertEqual(package["material"]["title"], "Shell")

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

        package = imported_article("https://example.com/notes", fetch_text, fetch_bytes, ["Web"])
        self.assertEqual(package["material"]["title"], "Notes")
        self.assertIn("```fnmn-interactive\nhttps://example.com/notes\n#chart\n```", package["body"])
        self.assertNotIn("draw()", package["body"])
        path, encoded = next(iter(package["files"].items()))
        self.assertEqual(len(package["files"]), 1)
        self.assertTrue(path.startswith("assets/") and path.endswith(".png"))
        self.assertEqual(encoded, b"png")
        self.assertIn(f"]({path})", package["body"])
        self.assertEqual(seen, [("text", "https://example.com/notes"), ("bytes", "https://example.com/pic.png")])

    def test_missing_picture_keeps_article_without_broken_image(self):
        source = "<html><body><article><p>Hi</p><img src='pic.png'></article></body></html>"

        def fetch_bytes(url):
            raise OSError("missing")

        package = imported_article("https://example.com/notes", lambda url: source, fetch_bytes, [])
        self.assertIn("Hi", package["body"])
        self.assertNotIn("assets/", package["body"])
        self.assertEqual(package["files"], {})

    def test_missing_video_keeps_article_without_video_block(self):
        source = "<html><body><article><p>Hi</p><video src='clip.mp4'></video></article></body></html>"

        def fetch_bytes(url):
            raise OSError("404")

        package = imported_article("https://example.com/notes", lambda url: source, fetch_bytes, [])
        self.assertIn("Hi", package["body"])
        self.assertNotIn("fnmn-video", package["body"])
        self.assertEqual(package["files"], {})

    def test_refused_page_is_read_from_the_rendered_browser_page(self):
        def fetch_text(url):
            raise OSError("403 Forbidden")

        rendered = "<html><body><article><h1>Notes</h1><p>Body from the browser.</p></article></body></html>"
        package = imported_article("https://example.com/notes", fetch_text, lambda url: b"", [], lambda url: rendered)
        self.assertIn("Body from the browser.", package["body"])

    def test_script_shell_is_read_from_the_rendered_browser_page(self):
        shell = "<html><body><div id='root'></div><script>boot()</script></body></html>"
        rendered = "<html><body><article><p>Filled by the page script.</p></article></body></html>"
        package = imported_article("https://example.com/app", lambda url: shell, lambda url: b"", [], lambda url: rendered)
        self.assertIn("Filled by the page script.", package["body"])

    def test_redirected_page_resolves_pictures_from_its_final_address(self):
        source = with_base(
            "<html><head><title>Q</title></head><body><article><p>Text.</p><img src='assets/a.png'></article></body></html>",
            "https://example.com/quanta/",
        )
        seen = []

        def fetch_bytes(url):
            seen.append(url)
            return b"png"

        imported_article("https://example.com/quanta", lambda url: source, fetch_bytes, [])
        self.assertEqual(seen, ["https://example.com/quanta/assets/a.png"])

    def test_readable_page_does_not_open_the_browser(self):
        source = "<html><body><article><p>Plain page.</p></article></body></html>"

        def render_text(url):
            raise AssertionError("browser opened for a readable page")

        package = imported_article("https://example.com/notes", lambda url: source, lambda url: b"", [], render_text)
        self.assertIn("Plain page.", package["body"])

    def test_page_refused_by_browser_too_reports_both_reasons(self):
        def fail(reason):
            def fetch(url):
                raise OSError(reason)
            return fetch

        with self.assertRaises(ImportFailure) as caught:
            imported_article("https://example.com/notes", fail("403 Forbidden"), lambda url: b"", [], fail("HTTP 403"))
        self.assertEqual(caught.exception.phase, "fetchingPage")
        self.assertIn("Chrome: HTTP 403; 403 Forbidden", str(caught.exception))

    def test_heading_with_math_stays_one_section(self):
        source = """
        <html><body><article>
          <h2>The <script type="math/tex">\\sigma</script>-algebra</h2>
          <p>Next paragraph.</p>
        </article></body></html>
        """
        package = imported_article("https://example.com/sigma", lambda url: source, lambda url: b"", [])
        self.assertIn("## The $\\sigma$-algebra", package["body"])
        self.assertEqual(package["sections"], [])

    def test_html_with_encoding_declaration_imports(self):
        source = '<?xml version="1.0" encoding="iso-8859-1"?><html><head><title>Notes</title></head><body><article><p>Текст with enough words to read.</p></article></body></html>'
        package = imported_article("https://example.com/notes", lambda url: source, lambda url: b"", [])
        self.assertIn("Текст with enough words to read.", package["body"])

    def test_unread_page_fails_during_page_fetch(self):
        def fetch_text(url):
            raise OSError("down")

        with self.assertRaises(ImportFailure) as caught:
            imported_article("https://example.com/notes", fetch_text, lambda url: b"", [])
        self.assertEqual(caught.exception.phase, "fetchingPage")


if __name__ == "__main__":
    unittest.main()

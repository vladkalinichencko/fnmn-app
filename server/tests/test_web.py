import unittest
from unittest.mock import patch

import web


class FakeTab:
    def __init__(self, page: str, status: int | None = None):
        self.page = page
        self.status = status
        self.url = "https://example.com/final"

    def goto(self, url):
        pass

    def settle(self):
        pass

    def document_status(self):
        return self.status

    def html(self):
        return self.page


class RenderedTests(unittest.TestCase):
    def rendered(self, tab):
        job = patch("web.reader.job")
        mock = job.start()
        self.addCleanup(job.stop)
        mock.return_value.__enter__.return_value = tab
        return web._rendered("https://example.com")

    def test_a_browser_error_page_raises_like_a_network_error(self):
        tab = FakeTab('<html><body><div id="main-frame-error">dino</div></body></html>')
        with self.assertRaises(OSError):
            self.rendered(tab)

    def test_an_http_error_status_raises(self):
        with self.assertRaises(OSError):
            self.rendered(FakeTab("<html></html>", status=404))

    def test_a_page_comes_back_pinned_to_its_final_address(self):
        page = self.rendered(FakeTab("<html><head></head><body>text</body></html>"))
        self.assertIn('<base href="https://example.com/final">', page)


if __name__ == "__main__":
    unittest.main()

import unittest
from urllib.parse import urlparse

from publisher import homepage_of, publisher_of, site_name
from tests import fakes


def answering(*addresses):
    """A Web that serves a page at the given addresses and refuses everything else."""
    def text(url):
        if url not in addresses:
            raise OSError(f"HTTP 404 for {url}")
        return "<html><body>index</body></html>"

    return fakes.web(text=text)


class PublisherTests(unittest.TestCase):
    def test_a_post_belongs_to_the_section_that_answers_not_to_its_year(self):
        web = answering("https://blog.example/blog/", "https://blog.example/blog/2026/", "https://blog.example/")
        self.assertEqual(homepage_of(urlparse("https://blog.example/blog/2026/shape/"), web), "https://blog.example/blog/")

    def test_a_section_that_does_not_answer_leaves_the_front_page(self):
        web = answering("https://example.com/")
        self.assertEqual(homepage_of(urlparse("https://example.com/p/a-post"), web), "https://example.com/")

    def test_dates_are_not_sections(self):
        probed = []

        def text(url):
            probed.append(url)
            return "<html>index</html>"

        homepage = homepage_of(urlparse("https://example.com/2026/05/a-post/"), fakes.web(text=text))
        self.assertEqual(homepage, "https://example.com/")
        self.assertEqual(probed, [])

    def test_a_page_directly_on_the_site_is_the_sites_own(self):
        self.assertEqual(homepage_of(urlparse("https://example.com/a-post"), answering()), "https://example.com/")

    def test_a_site_that_cannot_be_asked_still_has_a_front_page(self):
        def refuse(url):
            raise OSError("blocked")

        self.assertEqual(homepage_of(urlparse("https://example.com/notes/a/b"), fakes.web(text=refuse)), "https://example.com/")

    def test_only_the_first_sections_are_asked(self):
        probed = []

        def text(url):
            probed.append(url)
            raise OSError("404")

        homepage_of(urlparse("https://example.com/a/b/c/d/e"), fakes.web(text=text))
        self.assertEqual(probed, ["https://example.com/a/", "https://example.com/a/b/"])

    def test_the_site_names_itself_in_its_markup(self):
        page = '<html><head><meta property="og:site_name" content="  Alex L.\n Zhang "></head></html>'
        self.assertEqual(site_name(page), "Alex L. Zhang")
        self.assertEqual(site_name('<html><head><meta name="application-name" content="Notes"></head></html>'), "Notes")
        self.assertIsNone(site_name("<html><head><title>Notes</title></head></html>"))
        self.assertIsNone(site_name(""))

    def test_the_publisher_carries_the_name_only_when_the_site_has_one(self):
        web = answering("https://example.com/blog/")
        named = '<html><head><meta property="og:site_name" content="Example"></head></html>'
        self.assertEqual(
            publisher_of("https://example.com/blog/a", named, web),
            {"homepage": "https://example.com/blog/", "name": "Example"},
        )
        self.assertEqual(publisher_of("https://example.com/blog/a", "<html></html>", web), {"homepage": "https://example.com/blog/"})

    def test_an_address_that_is_not_a_web_page_has_no_publisher(self):
        self.assertIsNone(publisher_of("file:///tmp/a.html", "<html></html>", answering()))


if __name__ == "__main__":
    unittest.main()

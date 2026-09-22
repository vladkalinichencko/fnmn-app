import unittest
from urllib.parse import urljoin

import httpx
from lxml import html

from fnmn_service import import_web_article
from html_markdown import _picture, _selector, article_markdown


PAGES = (
    (
        "https://distill.pub/2017/momentum/",
        "Why Momentum Really Works",
        "We begin with gradient descent.",
        "w^{k+1} = w^k-\\alpha\\nabla f(w^k).",
    ),
    (
        "https://distill.pub/2021/gnn-intro/",
        "A Gentle Introduction to Graph Neural Networks",
        "Graphs are all around us",
        None,
    ),
)


def _select(document, selector: str):
    if selector.startswith("#"):
        return document.xpath(f'//*[@id="{selector[1:]}"]')
    current = [document]
    for part in selector.split(" > "):
        tag, _, index = part.partition(":nth-of-type(")
        number = int(index[:-1])
        nxt = []
        for parent in current:
            same = [child for child in parent if getattr(child, "tag", None) == tag]
            if 1 <= number <= len(same):
                nxt.append(same[number - 1])
        current = nxt
    return current


def _crops(markdown: str) -> list[tuple[str, str | None]]:
    crops = []
    for part in markdown.split("```fnmn-interactive\n")[1:]:
        body = part.split("```", 1)[0].strip().splitlines()
        crops.append((body[0], body[1] if len(body) > 1 else None))
    return crops


class DistillTests(unittest.TestCase):
    def test_both_articles_keep_text_and_point_figures_at_the_live_page(self):
        for url, title, phrase, formula in PAGES:
            with self.subTest(url=url):
                self._check_page(url, title, phrase, formula)

    def _check_page(self, url: str, title: str, phrase: str, formula: str | None):
        source = httpx.get(url, follow_redirects=True, timeout=40, headers={"User-Agent": "FNMN/1.0 article reader"}).text
        document = html.fromstring(source)
        markdown, downloads = article_markdown(source, url)
        fetched = []

        def fetch_text(page: str) -> str:
            if page != url:
                raise AssertionError(page)
            return source

        def fetch_bytes(asset: str) -> bytes:
            response = httpx.get(asset, follow_redirects=True, timeout=40, headers={"User-Agent": "FNMN/1.0 article reader"})
            response.raise_for_status()
            self.assertGreater(len(response.content), 0)
            fetched.append(asset)
            return response.content

        package = import_web_article(url, fetch_text, fetch_bytes, ["Web"])
        self.assertEqual(package["material"]["title"], title)
        self.assertEqual(package["material"]["sourceURL"], url)
        self.assertIn(f"# {title}", package["body"])
        self.assertIn(phrase, package["body"])
        self.assertNotIn("dt-math[block]", package["body"])
        if formula:
            self.assertIn(f"$$\n{formula}\n$$", package["body"])
        self.assertEqual(package["body"], markdown)

        root = document.find(".//d-article")
        if root is None:
            root = document.find(".//dt-article")
        figures = [node for node in root.xpath(".//figure") if not node.xpath("ancestor::figure")]
        self.assertGreater(len(figures), 0)
        crops = _crops(markdown)
        figure_crops = [selector for _, selector in crops if selector]
        for figure in figures:
            selector = _selector(figure)
            if _picture(figure):
                self.assertNotIn(selector, figure_crops)
            else:
                self.assertIn(selector, figure_crops)
        for page, selector in crops:
            self.assertEqual(page.rstrip("/"), url.rstrip("/"))
            found = _select(document, selector)
            self.assertEqual([node.tag for node in found], ["figure"], selector)

        scripts = {urljoin(url, src) for src in document.xpath("//script[@src]/@src")}
        styles = {urljoin(url, href) for href in document.xpath('//link[@rel="stylesheet"]/@href')}
        for asset in downloads.values():
            self.assertNotIn(asset, scripts)
            self.assertNotIn(asset, styles)
        self.assertEqual(set(fetched), set(downloads.values()))
        self.assertEqual(set(package["files"]), set(downloads))


if __name__ == "__main__":
    unittest.main()

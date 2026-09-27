import unittest
import sqlite3
import tempfile
from pathlib import Path

from browser_library import build_library, canonical_url, source_for
from browser_links_export import safari_tab_groups


class BrowserLibraryTests(unittest.TestCase):
    def test_safari_tab_groups_reads_only_named_live_web_tabs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SafariTabs.db"
            database = sqlite3.connect(path)
            database.execute(
                "CREATE TABLE bookmarks "
                "(id INTEGER, parent INTEGER, type INTEGER, title TEXT, url TEXT, deleted INTEGER, order_index INTEGER)"
            )
            database.executemany("INSERT INTO bookmarks VALUES (?, ?, ?, ?, ?, ?, ?)", [
                (1, 0, 1, "Self-studу", "", 0, 0),
                (2, 1, 0, "Article", "https://example.com/article", 0, 0),
                (3, 1, 0, "Deleted", "https://example.com/deleted", 1, 1),
                (4, 1, 0, "Start Page", "", 0, 2),
            ])
            database.commit()
            database.close()
            rows = list(safari_tab_groups(path, {"Self-studу"}))
        self.assertEqual([row["url"] for row in rows], ["https://example.com/article"])

    def test_canonical_url_removes_tracking_but_keeps_playlist(self):
        url = "https://www.youtube.com/watch?v=abc&list=PL1&utm_source=test"
        self.assertEqual(canonical_url(url), "https://youtube.com/watch?v=abc&list=PL1")

    def test_course_pages_share_the_course_as_source(self):
        source, kind = source_for("https://ocw.mit.edu/courses/18-06sc-linear-algebra/pages/syllabus/")
        self.assertEqual(source, "https://ocw.mit.edu/courses/18-06sc-linear-algebra")
        self.assertEqual(kind, "course")

    def test_youtube_video_with_playlist_uses_playlist(self):
        source, kind = source_for("https://youtube.com/watch?v=abc&list=PL1")
        self.assertEqual(source, "https://youtube.com/playlist?list=PL1")
        self.assertEqual(kind, "youtube_playlist")

    def test_substack_article_uses_author_catalog(self):
        source, kind = source_for("https://arxiviq.substack.com/p/an-article")
        self.assertEqual(source, "https://arxiviq.substack.com")
        self.assertEqual(kind, "author")

    def test_habr_company_uses_company_articles(self):
        source, kind = source_for("https://habr.com/ru/companies/yandex/articles/1077274/")
        self.assertEqual(source, "https://habr.com/ru/companies/yandex/articles")
        self.assertEqual(kind, "publisher")

    def test_saved_catalog_is_not_its_own_material(self):
        rows = [{"url": "https://example.com/", "title": "Example", "collection": "reading-list"}]
        source = build_library(rows)["sources"][0]
        self.assertEqual(source["url"], "https://example.com/")
        self.assertEqual(source["name"], "Example")
        self.assertEqual(source["materials"], [])

    def test_aliases_merge_without_losing_saved_urls(self):
        rows = [
            {"url": "https://archive.example/a", "title": "Article", "collection": "one"},
            {"url": "https://archive.example/b", "title": "Article", "collection": "two"},
        ]
        overrides = {
            row["url"]: {
                "material_url": "https://publisher.example/article",
                "source_url": "https://publisher.example/articles",
                "source_name": "Publisher",
                "kind": "publication",
            }
            for row in rows
        }
        material = build_library(rows, overrides)["sources"][0]["materials"][0]
        self.assertEqual(material["url"], "https://publisher.example/article")
        self.assertEqual(material["saved_urls"], ["https://archive.example/a", "https://archive.example/b"])
        self.assertEqual(material["saved_in"], ["one", "two"])
        self.assertEqual(material["found_in"], ["one", "two"])

    def test_unknown_site_requires_source_review(self):
        rows = [{"url": "https://unknown.example/post", "title": "Post", "collection": "one"}]
        review = build_library(rows)["review"]
        self.assertEqual(review, [{
            "url": "https://unknown.example/post",
            "reason": "source catalog is not verified",
        }])


if __name__ == "__main__":
    unittest.main()

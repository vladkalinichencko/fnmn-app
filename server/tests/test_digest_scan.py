import json
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from digest import instagram, scan, telegram, x
from digest.reading import SourceFailure
from digest.store import Store
from tests import fakes
from tests.test_digest_sources import FakeContext, FakeResponse, fixture, fake_web


class MergeTests(unittest.TestCase):
    def test_a_discovered_source_is_added_and_a_known_one_is_untouched(self):
        subscriptions = {
            "folders": ["ml"],
            "sources": [
                {"id": "x/karpathy", "network": "x", "handle": "karpathy", "name": "Andrej", "folders": ["ml"], "scope": "recommendations"},
            ],
        }
        additions = [
            {"id": "x/karpathy", "network": "x", "handle": "karpathy", "folders": []},
            {"id": "x/sama", "network": "x", "handle": "sama", "folders": [], "scanned": True},
        ]
        merged, fresh = scan.merge(subscriptions, additions, ["x"])
        self.assertEqual([source["id"] for source in fresh], ["x/sama"])
        self.assertEqual(merged["sources"][0]["folders"], ["ml"])
        self.assertEqual(merged["sources"][0]["scope"], "recommendations")
        self.assertEqual(merged["folders"], ["ml"])

    def test_a_scanned_source_the_profile_dropped_is_removed_but_a_manual_one_stays(self):
        subscriptions = {
            "folders": [],
            "sources": [
                {"id": "x/gone", "network": "x", "handle": "gone", "folders": ["ml"], "scanned": True},
                {"id": "x/manual", "network": "x", "handle": "manual", "folders": ["tech"]},
                {"id": "x/feed", "network": "x", "scope": "recommendations", "folders": []},
                {"id": "telegram/gone", "network": "telegram", "channel": "gone", "folders": [], "scanned": True},
            ],
        }
        merged, _ = scan.merge(subscriptions, [], ["x"])
        self.assertEqual(
            [source["id"] for source in merged["sources"]],
            ["x/manual", "x/feed", "telegram/gone"],
        )

    def test_account_rows_become_sources_without_the_profile_itself_or_reserved_pages(self):
        rows = [
            {"href": "/sama", "name": "Sam"},
            {"href": "/sama/", "name": "Sam Again"},
            {"href": "/home", "name": "Home"},
            {"href": "/explore", "name": "Explore"},
            {"href": "/", "name": ""},
        ]
        sources = scan._account_sources("x", rows, "owner")
        self.assertEqual(sources, [{"id": "x/sama", "network": "x", "handle": "sama", "folders": [], "scanned": True, "name": "Sam"}])


class FeedTab:
    """The parts of a reader tab the feed readers use: navigation stubs and scripted eval answers."""

    def __init__(self, selector_rows=None, eval_rows=None, markup=""):
        self.selector_rows = selector_rows or []
        self.eval_rows = eval_rows or []
        self.markup = markup
        self.url = "https://example.com"
        self.visited = []
        self.context = FakeContext()

    def goto(self, url, **kwargs):
        self.url = url
        self.visited.append(url)

    def html(self):
        return self.markup

    def wait_for_selector(self, *args, **kwargs):
        return None

    def wait_for_timeout(self, milliseconds):
        return None

    def wheel(self, delta):
        return None

    def eval(self, script):
        return self.eval_rows

    def eval_on_selector_all(self, selector, function):
        return self.selector_rows


class XFeedTests(unittest.TestCase):
    def test_the_recommendations_scope_reads_the_for_you_feed(self):
        tab = FeedTab(selector_rows=["https://x.com/sama/status/11", "/other/status/22", "not a link"])
        feed_source = {"id": "x/feed", "network": "x", "scope": "recommendations", "folders": ["ml"]}
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            result = x.collect(feed_source, fake_web(text=lambda url: fixture("tweet-20.json")), store, ["ml"], lambda stage: None, page=tab)
            self.assertIn("https://x.com/home", tab.visited)
            self.assertTrue(result.posts)
            for post in result.posts:
                self.assertEqual(post.source, "x/feed")
                self.assertTrue(post.author["handle"])

    def test_a_profile_source_still_reads_its_own_timeline(self):
        tab = FeedTab(selector_rows=["https://x.com/karpathy/status/33"])
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            source = {"id": "x/karpathy", "network": "x", "handle": "karpathy", "folders": ["ml"]}
            x.collect(source, fake_web(text=lambda url: fixture("tweet-20.json")), store, ["ml"], lambda stage: None, page=tab)
            self.assertIn("/karpathy", tab.url)


class InstagramFeedTests(unittest.TestCase):
    def test_the_recommendations_scope_reads_the_home_feed_with_each_author(self):
        tab = FeedTab(
            selector_rows=[{"href": "/p/CxYzAbCdEfG/", "user": "/studio/"}, {"href": "/p/Other123/", "user": ""}],
            markup=fixture("instagram-post.html"),
        )
        feed_source = {"id": "instagram/feed", "network": "instagram", "scope": "recommendations", "folders": ["design"]}
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            result = instagram.collect(feed_source, fake_web(), store, ["design"], lambda stage: None, page=tab)
            self.assertIn("https://www.instagram.com/", tab.visited)
            self.assertEqual(len(result.posts), 1)
            post = result.posts[0]
            self.assertEqual(post.id, "instagram/studio/CxYzAbCdEfG")
            self.assertEqual(post.source, "instagram/feed")
            self.assertEqual(post.author["handle"], "studio")

    def test_pairs_drop_reserved_and_incomplete_rows(self):
        rows = [
            {"href": "/p/AAA/", "user": "/explore/"},
            {"href": "/p/BBB/", "user": "/"},
            {"href": "/p/CCC/", "user": "/real.user/"},
            "junk",
        ]
        self.assertEqual(instagram._pairs(rows), [("CCC", "real.user")])


class TelegramScopeTests(unittest.TestCase):
    def test_recommendations_are_refused_honestly(self):
        source = {"id": "telegram/feed", "network": "telegram", "scope": "recommendations"}
        with TemporaryDirectory() as folder:
            with self.assertRaises(SourceFailure):
                telegram.collect(source, fake_web(), Store(Path(folder)), [], lambda stage: None)

    def test_the_scan_lists_the_channels_the_cli_session_follows(self):
        chats = json.dumps([
            {"id": "-1", "title": "World Models", "type": "channel", "username": "gonzo_worlds"},
            {"id": "-2", "title": "Private", "type": "channel"},
            {"id": "-3", "title": "A group", "type": "supergroup", "username": "somegroup"},
        ])
        done = subprocess.CompletedProcess([], 0, stdout=chats, stderr="")
        with patch.object(scan.shutil, "which", return_value="/usr/local/bin/telegram"), \
                patch.object(scan.subprocess, "run", return_value=done):
            sources = scan._telegram()
        self.assertEqual(
            sources,
            [{"id": "telegram/gonzo_worlds", "network": "telegram", "channel": "gonzo_worlds",
              "folders": [], "scanned": True, "name": "World Models"}],
        )


if __name__ == "__main__":
    unittest.main()

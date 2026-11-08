import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import httpx

from digest import instagram, telegram, x
from digest.reading import save_photo
from digest.store import Store
from tests.test_digest_store import png
from web import Web

FIXTURES = Path(__file__).resolve().parent.parent / "digest" / "fixtures"


def fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def source(**values) -> dict:
    return {"id": "x/karpathy", "network": "x", "handle": "karpathy", "folders": ["ml"], **values}


class FakeWeb(Web):
    def __new__(cls, text=None, bytes=None):
        return super().__new__(cls, text or (lambda url: ""), bytes or (lambda url: png()), None, None)


class FakePage:
    """What the parsers ask of a Playwright page: the markup after a navigation."""

    def __init__(self, markup: str):
        self.markup = markup
        self.url = "https://example.com"

    def goto(self, url, **kwargs):
        return None

    def content(self):
        return self.markup

    def wait_for_timeout(self, milliseconds):
        return None


class TelegramTests(unittest.TestCase):
    def test_the_fixture_page_reads_into_posts(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            web = FakeWeb(text=lambda url: fixture("telegram.html"))
            result = telegram.collect(
                {"id": "telegram/telegram", "network": "telegram", "channel": "telegram", "folders": ["tech"]},
                web, store, ["tech"], lambda stage: None,
            )
            self.assertEqual(len(result.posts), 3)
            self.assertEqual(result.name, "Telegram News")
            media = [post for post in result.posts if post.media]
            self.assertEqual(len(media), 1)
            for post in result.posts:
                self.assertTrue(post.id.startswith("telegram/telegram/"))
                self.assertTrue(post.permalink.startswith("https://t.me/telegram/"))
                self.assertTrue(post.posted_at.endswith("Z"))
                self.assertTrue(post.text)


class XTests(unittest.TestCase):
    def test_a_plain_tweet_hydrates(self):
        payload = json.loads(fixture("tweet-20.json"))
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "jack", source(), FakeWeb(), store, ["ml"])
            self.assertEqual(post.id, "x/20")
            self.assertEqual(post.author, {"handle": "jack", "name": "jack"})
            self.assertEqual(post.text, "just setting up my twttr")
            self.assertEqual(post.posted_at, "2006-03-21T20:50:14Z")
            self.assertIsNone(post.context)

    def test_a_quote_carries_the_quoted_post_and_its_picture(self):
        payload = json.loads(fixture("tweet-quote.json"))
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "karpathy", source(), FakeWeb(), store, ["ml"])
            self.assertEqual(post.context["kind"], "quote")
            self.assertEqual(post.context["post"]["author"]["handle"], "hardmaru")
            self.assertEqual(post.context["post"]["text"], "A post being quoted.")
            self.assertEqual(len(post.media), 1)
            self.assertEqual(post.stats["likes"], 812)

    def test_a_reply_carries_the_post_it_answers(self):
        payload = json.loads(fixture("tweet-reply.json"))
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "karpathy", source(), FakeWeb(), store, ["ml"])
            self.assertEqual(post.context["kind"], "reply")
            self.assertEqual(post.context["post"]["text"], "A post being answered.")

    def test_a_tweet_that_is_gone_is_skipped(self):
        self.assertIsNone(x._tweet(FakeWeb(text=lambda url: json.dumps({"__typename": "TweetTombstone"})), "1"))


class PictureTests(unittest.TestCase):
    def test_a_picture_the_network_refuses_is_left_out(self):
        def refuse(url):
            request = httpx.Request("GET", url)
            raise httpx.HTTPStatusError("403", request=request, response=httpx.Response(403, request=request))

        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            web = FakeWeb(bytes=refuse)
            self.assertIsNone(save_photo(web, store, "x/1", 0, "https://pbs.twimg.com/media/a.jpg"))
            post = x._post(json.loads(fixture("tweet-quote.json")), "karpathy", source(), web, store, ["ml"])
            self.assertEqual(post.media, [])
            self.assertTrue(post.text)


class InstagramTests(unittest.TestCase):
    def test_a_post_page_reads_its_caption_picture_and_time(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = instagram._post(
                FakePage(fixture("instagram-post.html")), "studio", "CxYzAbCdEfG",
                {"id": "instagram/studio", "network": "instagram", "handle": "studio", "folders": ["design"]},
                FakeWeb(), store, ["design"],
            )
            self.assertEqual(post.id, "instagram/studio/CxYzAbCdEfG")
            self.assertEqual(post.text, "Two pencils and one idea. Drawing the same shape until it stops arguing.")
            self.assertEqual(len(post.media), 1)
            self.assertEqual(post.posted_at, "2026-03-03T10:00:00Z")
            self.assertEqual(post.author["handle"], "studio")

    def test_a_description_without_a_caption_keeps_the_text(self):
        self.assertIsNone(instagram._caption(None))
        self.assertEqual(instagram._caption("12 likes"), "12 likes")


if __name__ == "__main__":
    unittest.main()

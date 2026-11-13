import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import httpx
from lxml import html

from digest import instagram, telegram, x
from digest.reading import save_photo
from digest.store import Store
from tests import fakes
from tests.test_digest_store import png
from web import Web

FIXTURES = Path(__file__).resolve().parent.parent / "digest" / "fixtures"


def fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def source(**values) -> dict:
    return {"id": "x/karpathy", "network": "x", "handle": "karpathy", "folders": ["ml"], **values}


def fake_web(text=None, bytes=None) -> Web:
    return fakes.web(text=text or (lambda url: ""), bytes=bytes or (lambda url: png()))


class FakeResponse:
    status = 200

    def body(self):
        return png()


class FakeRequest:
    def get(self, url, timeout=None):
        return FakeResponse()


class FakeContext:
    request = FakeRequest()


class FakePage:
    """What the parsers ask of a reader tab: the markup after a navigation."""

    def __init__(self, markup: str):
        self.markup = markup
        self.url = "https://example.com"
        self.context = FakeContext()

    def goto(self, url, **kwargs):
        return None

    def html(self):
        return self.markup

    def wait_for_timeout(self, milliseconds):
        return None


class TelegramTests(unittest.TestCase):
    def test_the_fixture_page_reads_into_posts(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            web = fake_web(text=lambda url: fixture("telegram.html"))
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

    def test_the_page_reader_uses_the_profile(self):
        def refuse(url):
            raise OSError("the profile page is the only reader")

        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            result = telegram.collect(
                {"id": "telegram/telegram", "network": "telegram", "channel": "telegram", "folders": ["tech"]},
                fake_web(text=refuse), store, ["tech"], lambda stage: None, page=FakePage(fixture("telegram.html")),
            )
            self.assertEqual(len(result.posts), 3)

    def test_an_album_keeps_every_photo(self):
        photos = "".join(
            f'<a class="tgme_widget_message_photo_wrap" style="background-image:url(\'https://cdn.telesco.pe/file/{index}.jpg\')"></a>'
            for index in range(12)
        )
        message = html.fromstring(
            '<div class="tgme_widget_message_wrap">'
            '<div class="tgme_widget_message" data-post="channel/7">'
            '<div class="tgme_widget_message_text">album</div>'
            f'{photos}'
            '<time datetime="2026-11-13T10:00:00+00:00">x</time>'
            '</div></div>'
        )
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = telegram._post(message, "channel", {"id": "telegram/channel"}, fake_web(), store, ["tech"])
            self.assertEqual(len(post.media), 12)

    def test_a_video_carries_its_file(self):
        message = html.fromstring(
            '<div class="tgme_widget_message_wrap">'
            '<div class="tgme_widget_message" data-post="channel/8">'
            '<i class="tgme_widget_message_video_thumb" style="background-image:url(\'https://cdn.telesco.pe/file/p.jpg\')"></i>'
            '<video class="tgme_widget_message_video js-message_video" src="https://cdn.telesco.pe/file/v.mp4?token=t"></video>'
            '<time datetime="2026-11-13T10:00:00+00:00">x</time>'
            '</div></div>'
        )
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = telegram._post(message, "channel", {"id": "telegram/channel"}, fake_web(), store, ["tech"])
            self.assertIsNotNone(post.video["file"])
            self.assertTrue(post.video["file"]["path"].endswith(".mp4"))
            self.assertIsNotNone(post.video["poster"])


class XTests(unittest.TestCase):
    def test_a_plain_tweet_hydrates(self):
        payload = json.loads(fixture("tweet-20.json"))
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "jack", source(), fake_web(), store, ["ml"])
            self.assertEqual(post.id, "x/20")
            self.assertEqual(post.author, {"handle": "jack", "name": "jack"})
            self.assertEqual(post.text, "just setting up my twttr")
            self.assertEqual(post.posted_at, "2006-03-21T20:50:14Z")
            self.assertIsNone(post.context)

    def test_a_quote_carries_the_quoted_post_and_its_picture(self):
        payload = json.loads(fixture("tweet-quote.json"))
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "karpathy", source(), fake_web(), store, ["ml"])
            self.assertEqual(post.context["kind"], "quote")
            self.assertEqual(post.context["post"]["author"]["handle"], "hardmaru")
            self.assertEqual(post.context["post"]["text"], "A post being quoted.")
            self.assertEqual(len(post.media), 1)
            self.assertEqual(post.stats["likes"], 812)

    def test_a_reply_carries_the_post_it_answers(self):
        payload = json.loads(fixture("tweet-reply.json"))
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "karpathy", source(), fake_web(), store, ["ml"])
            self.assertEqual(post.context["kind"], "reply")
            self.assertEqual(post.context["post"]["text"], "A post being answered.")

    def test_a_tweet_that_is_gone_is_skipped(self):
        self.assertIsNone(x._tweet(fake_web(text=lambda url: json.dumps({"__typename": "TweetTombstone"})), "1"))

    def test_an_album_keeps_every_photo(self):
        payload = {
            "id_str": "99",
            "user": {"screen_name": "karpathy", "name": "Andrej Karpathy"},
            "created_at": "2026-11-07T09:30:00.000Z",
            "text": "album",
            "mediaDetails": [
                {"type": "photo", "media_url_https": f"https://pbs.twimg.com/media/{index}.jpg"}
                for index in range(6)
            ],
        }
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "karpathy", source(), fake_web(), store, ["ml"])
            self.assertEqual(len(post.media), 6)

    def test_the_syndication_request_names_the_status(self):
        seen = []

        def text(url):
            seen.append(url)
            return json.dumps({"__typename": "TweetTombstone"})

        self.assertIsNone(x._tweet(fake_web(text=text), "12345"))
        self.assertIn("id=12345", seen[0])
        self.assertIn("cdn.syndication.twimg.com/tweet-result", seen[0])


class TelegramTimeTests(unittest.TestCase):
    def test_a_message_without_a_time_is_skipped(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            message = html.fromstring(
                '<div class="tgme_widget_message"><a data-post="channel/1"></a>'
                '<div class="tgme_widget_message_text">Hello</div></div>'
            )
            post = telegram._post(message, "channel", {"id": "telegram/channel"}, fake_web(), store, ["tech"])
            self.assertIsNone(post)


class PictureTests(unittest.TestCase):
    def test_a_picture_the_network_refuses_is_left_out(self):
        def refuse(url):
            request = httpx.Request("GET", url)
            raise httpx.HTTPStatusError("403", request=request, response=httpx.Response(403, request=request))

        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            web = fake_web(bytes=refuse)
            self.assertIsNone(save_photo(web, store, "x/1", 0, "https://pbs.twimg.com/media/a.jpg"))
            post = x._post(json.loads(fixture("tweet-quote.json")), "karpathy", source(), web, store, ["ml"])
            self.assertEqual(post.media, [])
            self.assertEqual(post.media_errors, 1)
            self.assertTrue(post.text)


class RepliesTab:
    """The permalink page as `_replies` drives it: navigation stubs plus the evaluated reply list."""

    def __init__(self, replies: list[dict]):
        self.replies = replies
        self.context = FakeContext()

    def goto(self, url, **kwargs):
        return None

    def wait_for_selector(self, *args, **kwargs):
        return None

    def eval(self, script):
        return self.replies


class RepliesTests(unittest.TestCase):
    def test_a_reply_carries_its_author_handle_and_avatar(self):
        replies = [{
            "author": "Grigory Sapunov",
            "handle": "gsapunov",
            "avatar": "https://pbs.twimg.com/profile_images/1/abc_normal.jpg",
            "text": "agreed",
            "permalink": "https://x.com/gsapunov/status/2",
        }]
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            comments = x._replies(RepliesTab(replies), fakes.post(), fake_web(), store, lambda url: png())
            comment = comments[0]
            self.assertEqual(comment["author"], "Grigory Sapunov")
            self.assertEqual(comment["handle"], "gsapunov")
            avatar = comment["avatar"]
            self.assertTrue(avatar["path"].startswith("media/x-1-reply-0"))
            self.assertTrue((store.root / avatar["path"]).exists())

    def test_a_reply_the_network_serves_no_avatar_for_keeps_the_rest(self):
        replies = [{"author": "a", "handle": None, "avatar": None, "text": "hi", "permalink": None}]
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            comments = x._replies(RepliesTab(replies), fakes.post(), fake_web(), store, lambda url: png())
            self.assertIsNone(comments[0]["avatar"])
            self.assertEqual(comments[0]["text"], "hi")


class InstagramTests(unittest.TestCase):
    def test_a_post_page_reads_its_caption_picture_and_time(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = instagram._post(
                FakePage(fixture("instagram-post.html")), "studio", "CxYzAbCdEfG",
                {"id": "instagram/studio", "network": "instagram", "handle": "studio", "folders": ["design"]},
                fake_web(), store, ["design"],
            )
            self.assertEqual(post.id, "instagram/studio/CxYzAbCdEfG")
            self.assertEqual(post.text, "Two pencils and one idea. Drawing the same shape until it stops arguing.")
            self.assertEqual(len(post.media), 1)
            self.assertEqual(post.posted_at, "2026-03-03T10:00:00Z")
            self.assertEqual(post.author["handle"], "studio")

    def test_a_description_without_a_caption_keeps_the_text(self):
        self.assertIsNone(instagram._caption(None))
        self.assertEqual(instagram._caption("12 likes"), "12 likes")

    def test_a_media_download_uses_the_page_context(self):
        def refuse(url):
            raise OSError("the article client is not the logged-in page")

        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = instagram._post(
                FakePage(fixture("instagram-post.html")), "studio", "CxYzAbCdEfG",
                {"id": "instagram/studio", "network": "instagram", "handle": "studio", "folders": ["design"]},
                fake_web(bytes=refuse), store, ["design"],
            )
            self.assertEqual(len(post.media), 1)

    def test_a_post_without_a_time_is_skipped(self):
        markup = (
            '<html><head>'
            '<meta property="og:description" content="12 likes, 0 comments - studio on March 3, 2026: &quot;A caption&quot;">'
            '<meta property="og:image" content="https://example.com/a.jpg">'
            '</head><body></body></html>'
        )
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = instagram._post(
                FakePage(markup), "studio", "abc",
                {"id": "instagram/studio", "network": "instagram", "handle": "studio", "folders": ["design"]},
                fake_web(), store, ["design"],
            )
            self.assertIsNone(post)


class SourceTableTests(unittest.TestCase):
    def test_one_table_serves_the_monitor_and_the_refresh(self):
        from digest import monitor, refresh
        from digest.reading import needs_browser

        self.assertIs(monitor.SOURCES, refresh.SOURCES)
        for network in monitor.SOURCES:
            self.assertTrue(needs_browser(network))
        self.assertFalse(needs_browser("none"))


if __name__ == "__main__":
    unittest.main()

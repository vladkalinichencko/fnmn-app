import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import httpx
from lxml import html

from digest import instagram, telegram, x
from digest.reading import mark_threads, save_photo
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

    def test_a_long_post_reads_its_whole_body_from_the_page(self):
        payload = json.loads(fixture("tweet-20.json"))
        payload["note_tweet"] = {"id": "Tm90ZVR3ZWV0"}

        class NoteTab:
            def goto(self, url, **kwargs):
                return None

            def wait_for_selector(self, *args, **kwargs):
                return None

            def eval(self, script):
                return "the whole long body, past the preview"

        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "jack", source(), fake_web(), store, ["ml"], page=NoteTab())
            self.assertEqual(post.text, "the whole long body, past the preview")

    def test_a_long_post_without_a_page_keeps_the_preview(self):
        payload = json.loads(fixture("tweet-20.json"))
        payload["note_tweet"] = {"id": "Tm90ZVR3ZWV0"}
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "jack", source(), fake_web(), store, ["ml"])
            self.assertEqual(post.text, "just setting up my twttr")

    def test_a_payload_that_carries_the_full_note_needs_no_page(self):
        payload = json.loads(fixture("tweet-20.json"))
        payload["note_tweet"] = {"full_text": "the whole long body, straight from the payload"}
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = x._post(payload, "jack", source(), fake_web(), store, ["ml"])
            self.assertEqual(post.text, "the whole long body, straight from the payload")


def tweet(status_id: str, user: str = "ada", text: str = "a post", parent: str | None = None, **extra) -> dict:
    payload = {
        "__typename": "Tweet",
        "id_str": status_id,
        "user": {"screen_name": user, "name": user.title()},
        "created_at": "2026-11-13T10:00:00.000Z",
        "text": text,
    }
    if parent:
        payload["in_reply_to_status_id_str"] = parent
    payload.update(extra)
    return payload


def tweets_web(payloads: dict[str, dict]) -> Web:
    def text(url):
        status_id = url.split("id=")[1].split("&")[0]
        return json.dumps(payloads[status_id])

    return fake_web(text=text)


class ChainTab:
    """A permalink page for `_entry`: `_conversation` gets its ancestor ids and the focal text, and a
    note read on an ancestor's own page gets the note body."""

    def __init__(self, ancestors: list[str], focal_text: str | None = None, note_text: str | None = None):
        self.ancestors = ancestors
        self.focal_text = focal_text
        self.note_text = note_text
        self.context = FakeContext()

    def goto(self, url, **kwargs):
        return None

    def wait_for_selector(self, *args, **kwargs):
        return None

    def wait_for_timeout(self, milliseconds):
        return None

    def eval(self, script):
        if "ancestors" in script:
            return {"ancestors": self.ancestors, "text": self.focal_text}
        return self.note_text


class XChainTests(unittest.TestCase):
    def entry(self, payloads: dict[str, dict], tab: ChainTab, focal: dict) -> list:
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            return x._entry(
                focal, "ada", source(), tweets_web(payloads), store, ["ml"], fetch=None, page=tab,
            )

    def test_a_reply_collects_its_whole_chain_as_posts(self):
        payloads = {
            "1": tweet("1", "root", "the root post"),
            "2": tweet("2", "mid", "the middle post", parent="1"),
            "3": tweet("3", "ada", "the reply", parent="2"),
        }
        posts = self.entry(payloads, ChainTab(["1", "2"]), payloads["3"])
        self.assertEqual([post.id for post in posts], ["x/1", "x/2", "x/3"])
        root, middle, reply = posts
        self.assertIsNone(root.context)
        self.assertEqual(middle.context["kind"], "reply")
        self.assertEqual(middle.context["post"]["id"], "x/1")
        self.assertEqual(middle.context["post"]["text"], "the root post")
        self.assertEqual(reply.context["kind"], "reply")
        self.assertEqual(reply.context["post"]["id"], "x/2")
        self.assertEqual(reply.context["post"]["text"], "the middle post")
        self.assertEqual(reply.context["post"]["author"]["handle"], "mid")

    def test_a_parent_the_page_did_not_show_reads_as_gone(self):
        payloads = {"9": tweet("9", "ghost", "a deleted post"), "3": tweet("3", "ada", "the reply", parent="9")}
        posts = self.entry(payloads, ChainTab([]), payloads["3"])
        self.assertEqual(len(posts), 1)
        self.assertEqual(posts[0].context, {"kind": "reply", "post": None})

    def test_a_tombstone_ancestor_breaks_the_chain_above_it(self):
        payloads = {
            "1": {"__typename": "TweetTombstone"},
            "2": tweet("2", "mid", "the middle post", parent="1"),
            "3": tweet("3", "ada", "the reply", parent="2"),
        }

        def text(url):
            status_id = url.split("id=")[1].split("&")[0]
            return json.dumps(payloads[status_id])

        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            posts = x._entry(payloads["3"], "ada", source(), fake_web(text=text), store, ["ml"], fetch=None, page=ChainTab(["1", "2"]))
        self.assertEqual([post.id for post in posts], ["x/2", "x/3"])
        middle, reply = posts
        self.assertEqual(middle.context, {"kind": "reply", "post": None})
        self.assertEqual(reply.context["post"]["id"], "x/2")

    def test_the_chain_stops_at_the_limit_with_the_nearest_ancestors(self):
        payloads = {str(index): tweet(str(index), f"u{index}", f"post {index}", parent=str(index - 1) if index > 1 else None) for index in range(1, 9)}
        payloads["8"] = tweet("8", "ada", "the reply", parent="7")
        ancestors = [str(index) for index in range(1, 8)]
        posts = self.entry(payloads, ChainTab(ancestors), payloads["8"])
        self.assertEqual([post.id for post in posts], ["x/3", "x/4", "x/5", "x/6", "x/7", "x/8"])
        self.assertIsNone(posts[0].context)
        self.assertEqual(posts[-1].context["post"]["id"], "x/7")

    def test_a_reply_with_a_note_tweet_reads_its_whole_body_from_the_page(self):
        payloads = {
            "1": tweet("1", "root", "the root post"),
            "2": tweet("2", "ada", "preview…", parent="1", note_tweet={"id": "bm90ZQ"}),
        }
        posts = self.entry(payloads, ChainTab(["1"], focal_text="the whole reply body"), payloads["2"])
        reply = posts[-1]
        self.assertEqual(reply.text, "the whole reply body")
        self.assertEqual(reply.context["post"]["text"], "the root post")

    def test_a_plain_post_never_opens_the_permalink_page(self):
        payloads = {"5": tweet("5", "ada", "just a post")}

        class NoPage:
            def goto(self, url, **kwargs):
                raise AssertionError("a plain post needs no page")

        posts = self.entry(payloads, NoPage(), payloads["5"])
        self.assertEqual([post.id for post in posts], ["x/5"])
        self.assertIsNone(posts[0].context)


class MarkThreadsTests(unittest.TestCase):
    def collected(self, post_id: str, at: str, handle: str = "chan", source_id: str = "telegram/chan") -> object:
        from digest.store import Post

        return Post(
            id=post_id, network="telegram", source=source_id,
            author={"handle": handle, "name": handle},
            permalink=f"https://t.me/{handle}/{post_id}", posted_at=at, text="t",
        )

    def test_a_run_inside_the_gap_shares_the_first_post_id(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            posts = [
                self.collected("telegram/chan/1", "2026-11-13T10:00:00Z"),
                self.collected("telegram/chan/2", "2026-11-13T10:05:00Z"),
                self.collected("telegram/chan/3", "2026-11-13T10:30:00Z"),
            ]
            mark_threads(posts, store)
            self.assertIsNone(posts[0].thread)
            self.assertEqual(posts[1].thread, "telegram/chan/1")
            self.assertEqual(posts[2].thread, "telegram/chan/1")

    def test_a_gap_past_the_threshold_starts_a_new_thread(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            posts = [
                self.collected("telegram/chan/1", "2026-11-13T10:00:00Z"),
                self.collected("telegram/chan/2", "2026-11-13T10:45:00Z"),
            ]
            mark_threads(posts, store)
            self.assertIsNone(posts[1].thread)

    def test_different_authors_and_sources_never_share_a_thread(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            posts = [
                self.collected("x/1", "2026-11-13T10:00:00Z", handle="a", source_id="x/recommendations"),
                self.collected("x/2", "2026-11-13T10:01:00Z", handle="b", source_id="x/recommendations"),
                self.collected("x/3", "2026-11-13T10:02:00Z", handle="a", source_id="x/other"),
            ]
            for post in posts:
                post.network = "x"
            mark_threads(posts, store)
            self.assertTrue(all(post.thread is None for post in posts))

    def test_a_run_chains_onto_the_thread_the_store_already_holds(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            earlier = self.collected("telegram/chan/1", "2026-11-13T10:00:00Z")
            earlier.thread = "telegram/chan/1"
            store.append([earlier])
            fresh = self.collected("telegram/chan/2", "2026-11-13T10:10:00Z")
            mark_threads([fresh], store)
            self.assertEqual(fresh.thread, "telegram/chan/1")


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
    def test_a_reply_carries_its_author_handle(self):
        replies = [{
            "author": "Grigory Sapunov",
            "handle": "gsapunov",
            "text": "agreed",
            "permalink": "https://x.com/gsapunov/status/2",
        }]
        comments = x._replies(RepliesTab(replies), fakes.post())
        self.assertEqual(comments, replies)

    def test_a_reply_without_a_handle_or_link_still_reads(self):
        replies = [{"author": "a", "handle": None, "text": "hi", "permalink": None}]
        comments = x._replies(RepliesTab(replies), fakes.post())
        self.assertEqual(comments[0]["text"], "hi")


class InstagramTests(unittest.TestCase):
    def test_a_post_page_reads_its_caption_picture_and_time(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            post = instagram._post(
                FakePage(fixture("instagram-post.html")), "studio", "p", "CxYzAbCdEfG",
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
                FakePage(fixture("instagram-post.html")), "studio", "p", "CxYzAbCdEfG",
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
                FakePage(markup), "studio", "p", "abc",
                {"id": "instagram/studio", "network": "instagram", "handle": "studio", "folders": ["design"]},
                fake_web(), store, ["design"],
            )
            self.assertIsNone(post)

    def test_a_post_page_is_opened_under_its_author(self):
        """The bare `/p/` URL answers the logged-in browser a rate-limited error page; the author-scoped
        one loads, so the collector must build `/{handle}/p/{code}/`."""

        class RecordingPage(FakePage):
            def __init__(self, markup):
                super().__init__(markup)
                self.urls = []

            def goto(self, url, **kwargs):
                self.urls.append(url)

        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            page = RecordingPage(fixture("instagram-post.html"))
            instagram._post(
                page, "studio", "reel", "CxYzAbCdEfG",
                {"id": "instagram/studio", "network": "instagram", "handle": "studio", "folders": ["design"]},
                fake_web(), store, ["design"],
            )
            self.assertEqual(page.urls, ["https://www.instagram.com/studio/reel/CxYzAbCdEfG/"])


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

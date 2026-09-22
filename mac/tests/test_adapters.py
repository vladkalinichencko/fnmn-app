import io
import json
import tarfile
import unittest
from pathlib import Path

from adapter_arxiv import paper_id
from adapter_youtube import youtube_package
from fnmn_service import ImportFailure, import_link
from sources import source_kind


def archive(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as packed:
        for name, blob in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(blob)
            packed.addfile(info, io.BytesIO(blob))
    return buffer.getvalue()


PAPER = b"""\\documentclass{article}
\\title{Local title}
\\author{Local author}
\\begin{document}
\\maketitle
\\begin{abstract}
Tokens.
\\end{abstract}
\\input{sections/intro}
\\section{Model}
The \\( \\sigma \\)-algebra.
\\[
E = mc^2
\\]
\\begin{equation}
a = b
\\end{equation}
\\includegraphics{figures/plot.png}
\\cite{vaswani}
% \\input{secret}
\\end{document}
"""

ATOM = """<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>Attention Is All You Need</title>
    <author><name>Ashish Vaswani</name></author>
    <author><name>Noam Shazeer</name></author>
  </entry>
</feed>
"""


class SourceTests(unittest.TestCase):
    def test_kind_matches_the_app_classifier(self):
        self.assertEqual(source_kind("https://example.com/post"), "web")
        self.assertEqual(source_kind("https://youtu.be/abc"), "youtube")
        self.assertEqual(source_kind("https://www.youtube.com/watch?v=abc"), "youtube")
        self.assertEqual(source_kind("https://arxiv.org/abs/1706.03762"), "arxiv")
        self.assertEqual(source_kind("https://arxiv.org/pdf/1706.03762.pdf"), "arxiv")
        self.assertEqual(source_kind("https://x.com/someone/status/1"), "x")
        self.assertEqual(source_kind("https://twitter.com/someone/status/1"), "x")
        self.assertEqual(source_kind("https://name.substack.com/p/hello"), "substack")
        self.assertEqual(source_kind("https://chatgpt.com/share/abc"), "chatgpt")
        self.assertEqual(source_kind("https://example.com/paper.pdf"), "pdf")
        self.assertIsNone(source_kind("ftp://example.com/a"))

    def test_paper_id_keeps_version_and_old_category(self):
        self.assertEqual(paper_id("https://arxiv.org/abs/1706.03762v2"), "1706.03762v2")
        self.assertEqual(paper_id("https://arxiv.org/pdf/1706.03762.pdf"), "1706.03762")
        self.assertEqual(paper_id("https://arxiv.org/abs/hep-th/9901001"), "hep-th/9901001")
        self.assertIsNone(paper_id("https://arxiv.org/"))


class AdapterTests(unittest.TestCase):
    def test_arxiv_source_becomes_the_same_markdown_package(self):
        blob = archive({
            "main.tex": PAPER,
            "sections/intro.tex": b"\\section{Intro}\nSee the model.\n",
            "secret.tex": b"HIDDEN\n",
            "figures/plot.png": b"png-bytes",
        })
        seen = []

        def fetch_text(url):
            seen.append(url)
            return ATOM

        def fetch_bytes(url):
            seen.append(url)
            return blob

        package = import_link("https://arxiv.org/abs/1706.03762v2", fetch_text, fetch_bytes, [])
        body = package["body"]
        self.assertEqual(package["material"]["sourceURL"], "https://arxiv.org/abs/1706.03762v2")
        self.assertEqual(package["material"]["title"], "Attention Is All You Need")
        self.assertEqual(package["material"]["byline"], "Ashish Vaswani, Noam Shazeer")
        self.assertIn("https://export.arxiv.org/e-print/1706.03762v2", seen)
        self.assertIn("## Intro", body)
        self.assertIn("## Model", body)
        self.assertIn("$ \\sigma $", body)
        self.assertIn("E = mc^2", body)
        self.assertIn("a = b", body)
        self.assertIn("[vaswani]", body)
        self.assertNotIn("HIDDEN", body)
        self.assertNotIn("\\input", body)
        image = next(iter(package["files"]))
        self.assertIn(image, body)
        self.assertEqual(package["files"][image], "cG5nLWJ5dGVz")
        self.assertIn("Model", [section["title"] for section in package["sections"]])

    def test_arxiv_pdf_stops_before_the_book_pipeline(self):
        with self.assertRaises(ImportFailure) as caught:
            import_link(
                "https://arxiv.org/abs/1706.03762",
                lambda url: ATOM,
                lambda url: b"%PDF-1.7",
                [],
            )
        self.assertIn("book pipeline", str(caught.exception))

    def test_x_post_uses_oembed_text(self):
        payload = {
            "author_name": "Ada",
            "html": '<blockquote class="twitter-tweet"><p>Hello<br>there <a href="https://t.co/aaaa">https://t.co/aaaa</a></p></blockquote>',
        }

        def fetch_text(url):
            self.assertIn("https://publish.x.com/oembed?url=", url)
            self.assertIn("x.com", url)
            return json.dumps(payload)

        package = import_link("https://x.com/ada/status/20", fetch_text, lambda url: b"", [])
        self.assertEqual(package["material"]["title"], "Ada")
        self.assertEqual(package["material"]["byline"], "Ada")
        self.assertIn("Hello\nthere", package["body"])
        self.assertNotIn("t.co", package["body"])

    def test_x_without_a_status_stops(self):
        with self.assertRaises(ImportFailure) as caught:
            import_link("https://x.com/ada", lambda url: "", lambda url: b"", [])
        self.assertIn("not a single post", str(caught.exception))

    def test_x_article_url_stops_until_the_body_is_public(self):
        with self.assertRaises(ImportFailure) as caught:
            import_link("https://x.com/i/article/2076946210397552640", lambda url: "", lambda url: b"", [])
        self.assertIn("article", str(caught.exception).lower())

    def test_chatgpt_share_walks_the_visible_branch(self):
        payload = {
            "title": "A proof",
            "current_node": "b",
            "mapping": {
                "a": {
                    "parent": None,
                    "message": {
                        "author": {"role": "system"},
                        "content": {"content_type": "text", "parts": ["hidden instructions"]},
                    },
                },
                "b": {
                    "parent": "c",
                    "message": {
                        "author": {"role": "assistant"},
                        "content": {"content_type": "text", "parts": ["Because $x$."]},
                    },
                },
                "c": {
                    "parent": "a",
                    "message": {
                        "author": {"role": "user"},
                        "content": {"content_type": "text", "parts": ["Why?"]},
                    },
                },
            },
        }

        def fetch_text(url):
            self.assertEqual(url, "https://chatgpt.com/share/abc-1")
            return json.dumps(payload)

        package = import_link("https://chatgpt.com/share/abc-1", fetch_text, lambda url: b"", [])
        body = package["body"]
        self.assertEqual(package["material"]["title"], "A proof")
        self.assertLess(body.index("## User"), body.index("## Assistant"))
        self.assertIn("Why?", body)
        self.assertIn("Because $x$.", body)
        self.assertNotIn("hidden instructions", body)

    def test_chatgpt_share_page_turns_copied_math_into_reader_delimiters(self):
        copied = (
            "Когда объект уходит, novelty ([[#Контракт одного состояния мира|$\\|w_t\\|/\\|z_t\\|$]]) падает.\n\n"
            "Если \\(R_6\\approx1\\), то\n\n"
            "\\[\n"
            "D=\n"
            "\\begin{bmatrix}\n"
            "d_1^\\top\n"
            "\\end{bmatrix}.\n"
            "\\]\n\n"
            "Смотри depth-guided back-projection. \ue200cite\ue202turn663420academia0\ue201 Дальше текст."
        )
        values = [
            {"_1": 2},
            "loaderData",
            {"_3": 4},
            "routes/share.$shareId.($action)",
            {"_5": 6},
            "serverResponse",
            {"_7": 8},
            "data",
            {"_9": 10, "_11": 12},
            "title",
            "Состояние моделирования мира",
            "linear_conversation",
            [13],
            {"_14": 15},
            "message",
            {"_16": 17, "_18": 19},
            "author",
            {"_20": 21},
            "content",
            {"_22": 23, "_24": 25},
            "role",
            "assistant",
            "content_type",
            "text",
            "parts",
            [copied],
        ]
        page = 'window.__reactRouterContext.streamController.enqueue(' + json.dumps(json.dumps(values)) + ")"

        package = import_link(
            "https://chatgpt.com/share/6ab2ce2c-5570-83e9-a018-e33a58793703",
            lambda url: page,
            lambda url: b"",
            [],
        )
        body = package["body"]
        self.assertEqual(package["material"]["title"], "Состояние моделирования мира")
        self.assertIn("$\\|w_t\\|/\\|z_t\\|$", body)
        self.assertNotIn("[[#", body)
        self.assertIn("$R_6\\approx1$", body)
        self.assertIn("$$\nD=\n\\begin{bmatrix}", body)
        self.assertNotIn("\\[", body)
        self.assertNotIn("\\(", body)
        self.assertNotIn("\ue200", body)

    def test_youtube_prepares_video_cues_from_timedtext(self):
        track = {
            "baseUrl": "https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=en",
            "languageCode": "en",
            "kind": None,
        }
        page = (
            "ytInitialPlayerResponse = "
            + json.dumps({
                "videoDetails": {"title": "Fixture talk", "author": "Channel"},
                "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [track]}},
            })
            + ";"
        )
        cues = {
            "events": [
                {"tStartMs": 0, "segs": [{"utf8": "Hello"}]},
                {"tStartMs": 1500, "segs": [{"utf8": "world"}]},
                {"tStartMs": 2000},
            ]
        }

        def fetch_text(url):
            if "oembed" in url:
                return json.dumps({"title": "Fixture talk", "author_name": "Channel"})
            if "watch?v=" in url:
                return page
            if "timedtext" in url:
                return json.dumps(cues)
            raise AssertionError(url)

        package = youtube_package("https://youtu.be/abcdefghijk", fetch_text, [])
        self.assertEqual(package["material"]["kind"], "video")
        self.assertEqual(package["material"]["id"], "youtube:abcdefghijk")
        self.assertEqual(package["material"]["title"], "Fixture talk")
        self.assertEqual(package["material"]["byline"], "Channel")
        self.assertEqual(package["folders"], [])
        self.assertEqual(package["body"], "Hello\n\nworld")
        transcripts = [block for block in package["blocks"] if block["kind"] == "transcript"]
        self.assertEqual([(block["startSeconds"], block["html"]) for block in transcripts], [(0.0, "Hello"), (1.5, "world")])
        video = next(block for block in package["blocks"] if block["kind"] == "video")
        self.assertEqual(video["mediaURL"], "https://www.youtube.com/embed/abcdefghijk")

    def test_server_leaves_youtube_to_the_phone(self):
        with self.assertRaises(ImportFailure) as caught:
            import_link("https://youtu.be/abcdefghijk", lambda page: "", lambda page: b"", [])
        self.assertIn("phone", str(caught.exception))

    def test_pdf_links_still_stop(self):
        with self.assertRaises(ImportFailure) as caught:
            import_link("https://example.com/paper.pdf", lambda page: "", lambda page: b"", [])
        self.assertIn("PDF", str(caught.exception))
        self.assertIn("does not prepare", str(caught.exception))

    def test_substack_page_uses_the_web_article(self):
        source = Path(__file__).with_name("fixture.html").read_text()
        package = import_link(
            "https://name.substack.com/p/hello",
            lambda url: source,
            lambda url: b"image-bytes",
            [],
        )
        self.assertEqual(package["material"]["sourceURL"], "https://name.substack.com/p/hello")
        self.assertIn("body", package)
        self.assertTrue(package["body"].strip())

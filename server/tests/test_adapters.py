import io
import json
import tarfile
import unittest
from unittest.mock import patch
from pathlib import Path

import pymupdf

from adapters.arxiv import paper_id
from adapters.youtube import cues_from_timedtext
from importer import import_link
from package import Document, ImportFailure, Video, package
from tests import fakes
from sources import source_kind


def archive(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as packed:
        for name, blob in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(blob)
            packed.addfile(info, io.BytesIO(blob))
    return buffer.getvalue()


def _one_page_pdf(heading: str, paragraph: str) -> bytes:
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 80), heading, fontsize=16)
    page.insert_text((72, 120), paragraph, fontsize=11)
    blob = document.tobytes()
    document.close()
    return blob


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
        rows = json.loads((Path(__file__).resolve().parents[2] / "fixtures/capture-sources.json").read_text())
        for row in rows:
            self.assertEqual(source_kind(row["url"]), row["source"], row["url"])

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

        delivered = import_link("https://arxiv.org/abs/1706.03762v2", [], fakes.web(fetch_text, fetch_bytes))
        package = delivered.package
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
        image = next(iter(delivered.files))
        self.assertIn(image, body)
        self.assertEqual(delivered.files[image], b"png-bytes")
        self.assertEqual(package["sections"], [])
        self.assertEqual(package["blocks"], [])

    def test_arxiv_pdf_goes_through_the_pdf_pipeline(self):
        pdf = _one_page_pdf("Introduction", "The transformer uses attention.")
        transcribed = Document("# Introduction\n\nThe transformer uses attention.\n", "Attention Is All You Need")
        with patch("adapters.pdf.transcribe", return_value=transcribed) as transcribe:
            package = import_link("https://arxiv.org/abs/1706.03762", [], fakes.web(lambda url: ATOM, lambda url: pdf)).package
        self.assertEqual(transcribe.call_args.args[:3], (pdf, "Attention Is All You Need", "Ashish Vaswani, Noam Shazeer"))
        self.assertIn("The transformer uses attention.", package["body"])

    def test_x_post_uses_oembed_text(self):
        payload = {
            "author_name": "Ada",
            "html": '<blockquote class="twitter-tweet"><p>Hello<br>there <a href="https://t.co/aaaa">https://t.co/aaaa</a></p></blockquote>',
        }

        def fetch_text(url):
            self.assertIn("https://publish.x.com/oembed?url=", url)
            self.assertIn("x.com", url)
            return json.dumps(payload)

        package = import_link("https://x.com/ada/status/20", [], fakes.web(fetch_text, lambda url: b"")).package
        self.assertEqual(package["material"]["title"], "Ada")
        self.assertEqual(package["material"]["byline"], "Ada")
        self.assertIn("Hello\nthere", package["body"])
        self.assertNotIn("t.co", package["body"])

    def test_x_without_a_status_stops(self):
        with self.assertRaises(ImportFailure) as caught:
            import_link("https://x.com/ada", [], fakes.web(lambda url: "", lambda url: b""))
        self.assertIn("not a single post", str(caught.exception))

    def test_x_article_url_stops_until_the_body_is_public(self):
        with self.assertRaises(ImportFailure) as caught:
            import_link("https://x.com/i/article/2076946210397552640", [], fakes.web(lambda url: "", lambda url: b""))
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

        package = import_link("https://chatgpt.com/share/abc-1", [], fakes.web(fetch_text, lambda url: b"")).package
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

        package = import_link("https://chatgpt.com/share/6ab2ce2c-5570-83e9-a018-e33a58793703", [], fakes.web(lambda url: page, lambda url: b"")).package
        body = package["body"]
        self.assertEqual(package["material"]["title"], "Состояние моделирования мира")
        self.assertIn("$\\|w_t\\|/\\|z_t\\|$", body)
        self.assertNotIn("[[#", body)
        self.assertIn("$R_6\\approx1$", body)
        self.assertIn("$$\nD=\n\\begin{bmatrix}", body)
        self.assertNotIn("\\[", body)
        self.assertNotIn("\\(", body)
        self.assertNotIn("\ue200", body)

    def test_chatgpt_share_drops_interface_entities_and_keeps_generated_apps_as_pages(self):
        app = {"app_block": {"language": "html", "title": "Demo", "content": '<div id="d" class="p-2">1 < 2</div><script>1</script>'}}
        text = (
            "message_reaction👍Look: image_group{\"query\":[\"a\"]}\n\n"
            "In entity[\"city\",\"Paris\",\"capital\"].\n\n---\n\n"
            f"genui{json.dumps(app)}\n\nDone."
        )
        payload = {
            "title": "T",
            "linear_conversation": [{"message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": [text]}}}],
        }
        delivery = import_link("https://chatgpt.com/share/abc-2", [], fakes.web(lambda url: json.dumps(payload), lambda url: b""))
        body = delivery.package["body"]
        self.assertNotIn("", body)
        self.assertNotIn("image_group", body)
        self.assertNotIn("---", body)
        self.assertIn("In Paris.", body)
        (path,) = delivery.files
        self.assertRegex(path, r"^assets/interactive-[0-9a-f]{16}\.html$")
        self.assertIn(f"```fnmn-interactive\n{path}\n```", body)
        self.assertIn('<div id="d" class="p-2">1 < 2</div>', delivery.files[path].decode())

    def test_youtube_prepares_video_cues_from_timedtext(self):
        payload = """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        Hello

        00:00:01.500 --> 00:00:02.000
        world
        """
        delivered = package(
            "https://youtu.be/abcdefghijk",
            Video("abcdefghijk", "Fixture talk", "Channel", cues_from_timedtext(payload)),
            [],
        ).package
        self.assertEqual(delivered["material"]["kind"], "video")
        self.assertEqual(delivered["material"]["id"], "youtube:abcdefghijk")
        self.assertEqual(delivered["material"]["title"], "Fixture talk")
        self.assertEqual(delivered["material"]["byline"], "Channel")
        self.assertEqual(delivered["folders"], [])
        self.assertEqual(delivered["body"], "Hello\n\nworld")
        transcripts = [block for block in delivered["blocks"] if block["kind"] == "transcript"]
        self.assertEqual([(block["startSeconds"], block["html"]) for block in transcripts], [(0.0, "Hello"), (1.5, "world")])
        video = next(block for block in delivered["blocks"] if block["kind"] == "video")
        self.assertEqual(video["mediaURL"], "https://www.youtube.com/embed/abcdefghijk")

    def test_youtube_link_is_read_by_the_youtube_adapter(self):
        video = Video("abcdefghijk", "Fixture talk")
        with patch.dict("importer.ADAPTERS", {"youtube": lambda url, web, report: video}):
            delivered = import_link("https://youtu.be/abcdefghijk", ["Videos"], fakes.web())
        self.assertEqual(delivered, package("https://youtu.be/abcdefghijk", video, ["Videos"]))

    def test_youtube_solver_passes_yt_dlp_checks(self):
        import hashlib

        import yt_dlp_ejs
        from yt_dlp.extractor.youtube.jsc._builtin.vendor import HASHES, VERSION

        self.assertEqual(yt_dlp_ejs.version, VERSION)
        core = hashlib.sha3_512(yt_dlp_ejs.yt.solver.core().encode()).hexdigest()
        lib = hashlib.sha3_512(yt_dlp_ejs.yt.solver.lib().encode()).hexdigest()
        self.assertEqual(core, HASHES["yt.solver.core.min.js"])
        self.assertEqual(lib, HASHES["yt.solver.lib.min.js"])

    def test_notebook_links_stop_instead_of_saving_the_github_page(self):
        url = "https://github.com/rasbt/LLMs-from-scratch/blob/main/ch05/11_qwen3/standalone-qwen3-moe-plus-kvcache.ipynb"
        with self.assertRaises(ImportFailure) as caught:
            import_link(url, [], fakes.web(lambda page: "", lambda page: b""))
        self.assertIn("Jupyter notebook", str(caught.exception))

    def test_pdf_link_goes_through_the_pdf_pipeline(self):
        pdf = _one_page_pdf("Notes", "Plain text.")
        with patch("adapters.pdf.transcribe", return_value=Document("# Notes\n\nPlain text.\n")) as transcribe:
            delivered = import_link("https://example.com/paper.pdf", [], fakes.web(bytes=lambda url: pdf))
        self.assertEqual(transcribe.call_args.args[0], pdf)
        self.assertEqual(delivered.package["material"]["title"], "Notes")

    def test_substack_page_uses_the_web_article(self):
        source = Path(__file__).with_name("fixture.html").read_text()
        package = import_link("https://name.substack.com/p/hello", [], fakes.web(lambda url: source, lambda url: b"image-bytes")).package
        self.assertEqual(package["material"]["sourceURL"], "https://name.substack.com/p/hello")
        self.assertIn("body", package)
        self.assertTrue(package["body"].strip())

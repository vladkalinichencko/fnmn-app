import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from adapters import youtube
from adapters.youtube import video_id_from_url

FIXTURE = Path(__file__).resolve().parents[2] / "Tests/FNMNCoreTests/Fixtures/youtube-urls.json"


class VideoIDTests(unittest.TestCase):
    def test_the_shared_address_list(self):
        lists = json.loads(FIXTURE.read_text(encoding="utf-8"))
        for address in lists["video"]:
            self.assertEqual(video_id_from_url(address), "abcdefghijk", address)
        for address in lists["none"]:
            self.assertIsNone(video_id_from_url(address), address)


class DownloadTests(unittest.TestCase):
    def test_download_reads_any_address_yt_dlp_reads(self):
        calls = []

        class FakeYDL:
            def __init__(self, options):
                self.options = options

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def download(self, urls):
                calls.append((urls, self.options["outtmpl"]))
                Path(self.options["outtmpl"] % {"ext": "mp4"}).write_bytes(b"mp4")

        with tempfile.TemporaryDirectory() as folder, patch.dict(sys.modules, {"yt_dlp": SimpleNamespace(YoutubeDL=FakeYDL)}):
            file = youtube.download("https://x.com/ryolu_/status/2119586846657454152", Path(folder), lambda *_: None)
        self.assertEqual(calls[0][0], ["https://x.com/ryolu_/status/2119586846657454152"])
        self.assertEqual(file.name, "ryolu_-status-2119586846657454152.mp4")

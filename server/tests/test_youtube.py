import json
import unittest
from pathlib import Path

from adapters.youtube import video_id_from_url

FIXTURE = Path(__file__).resolve().parents[2] / "Tests/FNMNCoreTests/Fixtures/youtube-urls.json"


class VideoIDTests(unittest.TestCase):
    def test_the_shared_address_list(self):
        lists = json.loads(FIXTURE.read_text(encoding="utf-8"))
        for address in lists["video"]:
            self.assertEqual(video_id_from_url(address), "abcdefghijk", address)
        for address in lists["none"]:
            self.assertIsNone(video_id_from_url(address), address)

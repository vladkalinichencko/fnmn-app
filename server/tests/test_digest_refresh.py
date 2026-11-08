import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from fastapi.testclient import TestClient

from digest.refresh import refresh
from digest.store import Post, Store
from service import app


def post(post_id: str = "x/1") -> Post:
    return Post(
        id=post_id,
        network="x",
        source="x/karpathy",
        author={"handle": "karpathy", "name": "Andrej Karpathy"},
        permalink="https://x.com/karpathy/status/1",
        posted_at="2026-11-07T09:30:00Z",
        text="A small model that reads the whole catalog.",
        folders=["ml"],
    )


class RefreshTests(unittest.TestCase):
    subscriptions = {"sources": [{"id": "x/karpathy", "network": "x", "handle": "karpathy", "folders": ["ml"]}]}

    def test_the_refreshed_media_comes_back(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            store.append([post()])

            def collect(module, source, folders):
                found = post()
                found.media = [{"path": "media/x-1-0.jpg", "width": 2, "height": 2}]
                return [found]

            self.assertEqual(refresh("x/1", store=store, collect=collect, subscriptions=self.subscriptions), [
                {"path": "media/x-1-0.jpg", "width": 2, "height": 2}
            ])

    def test_a_missing_post_is_not_found(self):
        with TemporaryDirectory() as folder:
            store = Store(Path(folder))
            with self.assertRaises(LookupError):
                refresh("x/none", store=store, collect=lambda *args: [], subscriptions=self.subscriptions)


class EndpointTests(unittest.TestCase):
    def test_a_missing_post_is_a_404(self):
        os.environ["FNMN_TOKEN"] = "test"
        client = TestClient(app)
        response = client.post(
            "/digest/refresh",
            json={"post_id": "x/missing"},
            headers={"Authorization": "Bearer test"},
        )
        self.assertEqual(response.status_code, 404)

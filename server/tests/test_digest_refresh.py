import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

from fastapi.testclient import TestClient

from digest.refresh import refresh
from digest.store import Store
from service import app
from tests.fakes import post


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

    def test_a_picture_in_the_store_is_served(self):
        os.environ["FNMN_TOKEN"] = "test"
        store = Store()
        store.media_dir.mkdir(parents=True, exist_ok=True)
        path = store.media_dir / f"probe-{uuid4().hex}.png"
        path.write_bytes(b"png")
        try:
            response = TestClient(app).get(
                f"/digest/media/{path.name}",
                headers={"Authorization": "Bearer test"},
            )
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.content, b"png")
        finally:
            path.unlink()

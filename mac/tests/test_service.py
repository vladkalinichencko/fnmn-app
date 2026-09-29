import os
import time
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from service import app


class ServiceTests(unittest.TestCase):
    def setUp(self):
        patcher = patch.dict(os.environ, {"FNMN_TOKEN": "test-token"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.client = TestClient(app, headers={"Authorization": "Bearer test-token"})

    def test_every_route_requires_the_token(self):
        anonymous = TestClient(app)
        self.assertEqual(anonymous.get("/health").status_code, 401)
        self.assertEqual(anonymous.post("/jobs", json={"url": "https://example.com"}).status_code, 401)
        self.assertEqual(self.client.get("/health").json(), {"status": "ok"})

    def test_job_reports_stages_and_hands_over_the_package(self):
        def fake_import(url, folders, web, report):
            report("ocr", 1, 2)
            time.sleep(0.2)
            report("ocr", 2, 2)
            return {"material": {"sourceURL": url}, "folders": folders}

        with patch("jobs.import_link", fake_import):
            job = self.client.post("/jobs", json={"url": "https://example.com/a.pdf", "folders": ["Books"]}).json()
            self.assertEqual(self.client.get(f"/jobs/{job['id']}/package").status_code, 409)
            while (status := self.client.get(f"/jobs/{job['id']}").json())["phase"] != "done":
                time.sleep(0.05)
        self.assertEqual((status["stage"], status["done"], status["total"]), ("ocr", 2, 2))
        delivered = self.client.get(f"/jobs/{job['id']}/package").json()
        self.assertEqual(delivered, {"material": {"sourceURL": "https://example.com/a.pdf"}, "folders": ["Books"]})

    def test_failed_job_keeps_its_reason(self):
        def fail(url, folders, web, report):
            raise ValueError("no text layer")

        with patch("jobs.import_link", fail):
            job = self.client.post("/jobs", json={"url": "https://example.com/a.pdf"}).json()
            while (status := self.client.get(f"/jobs/{job['id']}").json())["phase"] == "queued" or status["phase"] == "running":
                time.sleep(0.05)
        self.assertEqual((status["phase"], status["error"]), ("failed", "no text layer"))

    def test_video_job_hands_over_the_downloaded_file(self):
        def fake_download(url, folder, report):
            report("downloadingVideo", 1, 2)
            file = folder / "abcdefghijk.mp4"
            file.write_bytes(b"mp4")
            return file

        with patch("jobs.youtube.download", fake_download):
            job = self.client.post("/videos", json={"url": "https://youtu.be/abcdefghijk"}).json()
            while (status := self.client.get(f"/jobs/{job['id']}").json())["phase"] != "done":
                time.sleep(0.05)
        response = self.client.get(f"/jobs/{job['id']}/file")
        self.assertEqual((response.status_code, response.content), (200, b"mp4"))
        self.assertEqual(response.headers["content-type"], "video/mp4")


if __name__ == "__main__":
    unittest.main()

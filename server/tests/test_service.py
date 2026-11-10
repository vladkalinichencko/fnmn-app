import hashlib
import io
import json
import os
import tarfile
import time
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import jobs
from package import Delivery, Document
from service import app
from tests import fakes


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

    def test_job_reports_stages_and_hands_over_the_delivery_until_the_phone_stores_it(self):
        def fake_import(url, folders, web, report):
            report("ocr", 1, 2)
            time.sleep(0.2)
            report("ocr", 2, 2)
            return Delivery({"material": {"sourceURL": url}, "folders": folders}, {"assets/a.png": b"png"})

        with patch("jobs.import_link", fake_import):
            job = self.client.post("/jobs", json={"url": "https://example.com/a.pdf", "folders": ["Books"]}).json()
            self.assertEqual(self.client.get(f"/jobs/{job['id']}/package").status_code, 409)
            while (status := self.client.get(f"/jobs/{job['id']}").json())["phase"] != "done":
                time.sleep(0.05)
        self.assertEqual((status["stage"], status["done"], status["total"]), ("ocr", 2, 2))
        response = self.client.get(f"/jobs/{job['id']}/package")
        self.assertEqual(response.headers["content-type"], "application/x-tar")
        with tarfile.open(fileobj=io.BytesIO(response.content)) as archive:
            names = archive.getnames()
            package = json.loads(archive.extractfile("package.json").read())
        self.assertEqual(names, ["package.json", "assets/a.png"])
        self.assertEqual(package, {"material": {"sourceURL": "https://example.com/a.pdf"}, "folders": ["Books"]})
        self.assertEqual(self.client.get(f"/jobs/{job['id']}/package").status_code, 200)
        file = jobs.find(job["id"]).file
        self.assertEqual(self.client.delete(f"/jobs/{job['id']}").status_code, 204)
        self.assertFalse(file.exists())
        self.assertEqual(self.client.get(f"/jobs/{job['id']}").status_code, 404)

    def test_asking_again_for_a_link_or_file_gets_the_job_the_server_already_has(self):
        def fake_import(url, folders, web, report):
            time.sleep(0.2)
            return Delivery({"material": {"sourceURL": url}, "folders": folders}, {})

        with patch("jobs.import_link", fake_import), patch("jobs.import_file", lambda name, data, web, report: Delivery({"material": {}}, {})):
            first = self.client.post("/jobs", json={"url": "https://example.com/b.pdf"}).json()
            again = self.client.post("/jobs", json={"url": "https://example.com/b.pdf"}).json()
            other = self.client.post("/jobs", json={"url": "https://example.com/c.pdf"}).json()
            file = self.client.post("/files", params={"name": "a.pdf"}, content=b"one").json()
            file_again = self.client.post("/files", params={"name": "a.pdf"}, content=b"one").json()
            file_changed = self.client.post("/files", params={"name": "a.pdf"}, content=b"two").json()
            while self.client.get(f"/jobs/{first['id']}").json()["phase"] != "done":
                time.sleep(0.05)
            after_done = self.client.post("/jobs", json={"url": "https://example.com/b.pdf"}).json()
        self.assertEqual(first["id"], again["id"])
        self.assertEqual(first["id"], after_done["id"])
        self.assertNotEqual(first["id"], other["id"])
        self.assertEqual(file["id"], file_again["id"])
        self.assertNotEqual(file["id"], file_changed["id"])

    def test_a_link_nothing_could_be_made_of_arrives_as_the_link_with_its_reason(self):
        def fail(url, folders, web, report):
            raise ValueError("no text layer")

        with patch("jobs.import_link", fail), patch("jobs.LIVE", fakes.web()):
            job = self.client.post("/jobs", json={"url": "https://example.com/a.pdf", "folders": ["Books"]}).json()
            while (status := self.client.get(f"/jobs/{job['id']}").json())["phase"] == "queued" or status["phase"] == "running":
                time.sleep(0.05)
        self.assertEqual((status["phase"], status["error"]), ("done", "no text layer"))
        response = self.client.get(f"/jobs/{job['id']}/package")
        with tarfile.open(fileobj=io.BytesIO(response.content)) as archive:
            package = json.loads(archive.extractfile("package.json").read())
        self.assertEqual(package["material"]["id"], "link:https://example.com/a.pdf")
        self.assertEqual((package["material"]["kind"], package["folders"]), ("link", ["Books"]))

    def test_a_link_the_page_still_names_arrives_with_the_pages_title(self):
        def fail(url, folders, web, report):
            raise ValueError("no text layer")

        page = '<html><head><meta property="og:title" content="Quantum Kernels — Example"></head></html>'
        with patch("jobs.import_link", fail), patch("jobs.LIVE", fakes.web(text=lambda url: page)):
            job = self.client.post("/jobs", json={"url": "https://example.com/c/123", "folders": []}).json()
            while (status := self.client.get(f"/jobs/{job['id']}").json())["phase"] in ("queued", "running"):
                time.sleep(0.05)
        with tarfile.open(fileobj=io.BytesIO(self.client.get(f"/jobs/{job['id']}/package").content)) as archive:
            package = json.loads(archive.extractfile("package.json").read())
        self.assertEqual(package["material"]["title"], "Quantum Kernels")

    def _package_of_file(self, name, data):
        job = self.client.post("/files", params={"name": name}, content=data).json()
        while (status := self.client.get(f"/jobs/{job['id']}").json())["phase"] in ("queued", "running"):
            time.sleep(0.05)
        with tarfile.open(fileobj=io.BytesIO(self.client.get(f"/jobs/{job['id']}/package").content)) as archive:
            return status, json.loads(archive.extractfile("package.json").read())

    def test_a_markdown_file_becomes_a_material_known_by_its_bytes(self):
        data = "# Notes\n\nA paragraph written on the phone.".encode()
        status, package = self._package_of_file("notes.md", data)
        self.assertEqual((status["phase"], status["error"]), ("done", None))
        self.assertEqual(package["material"]["id"], "file:" + hashlib.sha256(data).hexdigest())
        self.assertEqual((package["material"]["kind"], package["material"]["title"]), ("article", "Notes"))
        self.assertIsNone(package["material"]["sourceURL"])
        self.assertIn("A paragraph written on the phone.", package["body"])

    def test_a_file_nothing_could_be_read_from_arrives_as_the_file_with_its_reason(self):
        status, package = self._package_of_file("slides.key", b"keynote")
        self.assertEqual(status["phase"], "done")
        self.assertIn(".key", status["error"])
        self.assertEqual(package["material"], {"id": "file:" + hashlib.sha256(b"keynote").hexdigest(),
                                               "kind": "link", "title": "slides"})

    def test_a_pdf_file_goes_through_the_pdf_pipeline(self):
        def fake_transcribe(pdf, title, authors, report):
            self.assertEqual(pdf, b"%PDF")
            return Document("# Paper\n\nText.", None, "A. Author")

        with patch("adapters.file.pdf.transcribe", fake_transcribe):
            _, package = self._package_of_file("paper.pdf", b"%PDF")
        self.assertEqual((package["material"]["title"], package["material"]["byline"]), ("Paper", "A. Author"))

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

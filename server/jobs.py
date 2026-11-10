"""Imports run as jobs so a phone can follow a book that takes hours.

A job moves queued -> running -> done | failed. While it runs, its adapter
reports the current stage and page count, which the phone reads by polling.
A link or file nothing could be made of is still done: its delivery is the
link or the file itself, and `error` says why.
A finished job keeps its file, the delivery archive or the video, until the
phone says it has stored it; then `forget` removes both. Jobs live in memory:
restarting the service forgets them.
"""

from __future__ import annotations

import hashlib
import logging
import tempfile
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from adapters import article, youtube
from importer import import_file, import_link
from package import Delivery, file_delivery, link_delivery, write_delivery
from web import LIVE

_LOG = logging.getLogger("uvicorn.error")
_FILES = Path(tempfile.gettempdir()) / "fnmn-job-files"

_POOL = ThreadPoolExecutor(max_workers=4)
_JOBS: dict[str, Job] = {}
_LOCK = threading.Lock()


@dataclass
class Job:
    id: str
    url: str
    folders: list[str]
    kind: str = "import"
    phase: str = "queued"
    stage: str | None = None
    done: int | None = None
    total: int | None = None
    error: str | None = None
    file: Path | None = None
    """The delivery archive of an `import` or a `file`, or the mp4 of a `videoFile`."""
    upload: bytes | None = None
    """What the phone sent for a `file` job, named by `url`, until the job has read it."""
    key: tuple = ()
    """What the job was asked for; the same ask finds the job again."""

    def status(self) -> dict:
        return {"id": self.id, "url": self.url, "phase": self.phase, "stage": self.stage,
                "done": self.done, "total": self.total, "error": self.error}


def submit(url: str, folders: list[str], kind: str = "import", upload: bytes | None = None) -> Job:
    """`import` prepares a package from a link, `file` from the `upload` named `url`; `videoFile` downloads
    a YouTube video as an mp4. The same ask while a job for it is queued, running or done without a fault
    gets that job back, so a phone that did not take the result asks again and takes it."""
    digest = hashlib.sha256(upload).hexdigest() if upload is not None else None
    key = (kind, url, tuple(folders), digest)
    with _LOCK:
        for known in _JOBS.values():
            if known.key == key and known.error is None and known.phase != "failed":
                return known
        job = Job(uuid.uuid4().hex, url, folders, kind, upload=upload, key=key)
        _JOBS[job.id] = job
    _POOL.submit(_run, job)
    return job


def find(job_id: str) -> Job | None:
    with _LOCK:
        return _JOBS.get(job_id)


def forget(job_id: str) -> Job | None:
    """The phone stored the job's result: its file and the job go."""
    with _LOCK:
        job = _JOBS.pop(job_id, None)
    if job is not None and job.file is not None:
        job.file.unlink(missing_ok=True)
    return job


def _run(job: Job) -> None:
    job.phase = "running"

    def report(stage: str, done: int | None, total: int | None) -> None:
        job.stage, job.done, job.total = stage, done, total

    try:
        _FILES.mkdir(parents=True, exist_ok=True)
        if job.kind == "videoFile":
            job.file = youtube.download(job.url, _FILES, report)
        else:
            archive = _FILES / f"{job.id}.tar"
            write_delivery(archive, _delivery(job, report))
            job.file = archive
    except Exception as error:
        _LOG.exception("job %s (%s) failed", job.id, job.url)
        job.phase, job.error = "failed", str(error)
        return
    job.phase = "done"


def _delivery(job: Job, report) -> Delivery:
    """What the link or file became, or else, when nothing could be made of it, the link or file itself."""
    if job.kind == "file":
        data, job.upload = job.upload or b"", None
        try:
            return import_file(job.url, data, LIVE, report)
        except Exception as failure:
            _LOG.exception("job %s (%s) kept the file as it is", job.id, job.url)
            job.error = str(failure)
            return file_delivery(job.url, data)
    try:
        return import_link(job.url, job.folders, LIVE, report)
    except Exception as failure:
        _LOG.exception("job %s (%s) kept the link as it is", job.id, job.url)
        job.error = str(failure)
        return link_delivery(job.url, article.title(job.url, LIVE), job.folders)

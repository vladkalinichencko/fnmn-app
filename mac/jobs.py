"""Imports run as jobs so a phone can follow a book that takes hours.

A job moves queued -> running -> done | failed. While it runs, its adapter
reports the current stage and page count, which the phone reads by polling.
A finished job keeps its file, the delivery archive or the video, until the
phone says it has stored it; then `forget` removes both. Jobs live in memory:
restarting the service forgets them.
"""

from __future__ import annotations

import tempfile
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from adapters import youtube
from importer import import_link
from package import write_delivery
from web import LIVE

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
    """The delivery archive of an `import`, or the mp4 of a `videoFile`."""

    def status(self) -> dict:
        return {"id": self.id, "url": self.url, "phase": self.phase, "stage": self.stage,
                "done": self.done, "total": self.total, "error": self.error}


def submit(url: str, folders: list[str], kind: str = "import") -> Job:
    """`import` prepares a package; `videoFile` downloads a YouTube video as an mp4."""
    job = Job(uuid.uuid4().hex, url, folders, kind)
    with _LOCK:
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
            delivery = import_link(job.url, job.folders, LIVE, report)
            archive = _FILES / f"{job.id}.tar"
            write_delivery(archive, delivery)
            job.file = archive
    except Exception as error:
        job.phase, job.error = "failed", str(error)
        return
    job.phase = "done"

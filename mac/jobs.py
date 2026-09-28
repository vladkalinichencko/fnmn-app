"""Imports run as jobs so a phone can follow a book that takes hours.

A job moves queued -> running -> done | failed. While it runs, its adapter
reports the current stage and page count, which the phone reads by polling.
Jobs live in memory: restarting the service forgets them.
"""

from __future__ import annotations

import threading
import uuid
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass, field

from importer import import_link
from web import LIVE

_POOL = ThreadPoolExecutor(max_workers=4)
_JOBS: dict[str, Job] = {}
_LOCK = threading.Lock()


@dataclass
class Job:
    id: str
    url: str
    folders: list[str]
    phase: str = "queued"
    stage: str | None = None
    done: int | None = None
    total: int | None = None
    error: str | None = None
    package: dict | None = None
    future: Future | None = field(default=None, repr=False)

    def status(self) -> dict:
        return {"id": self.id, "url": self.url, "phase": self.phase, "stage": self.stage,
                "done": self.done, "total": self.total, "error": self.error}


def submit(url: str, folders: list[str]) -> Job:
    job = Job(uuid.uuid4().hex, url, folders)
    with _LOCK:
        _JOBS[job.id] = job
    job.future = _POOL.submit(_run, job)
    return job


def find(job_id: str) -> Job | None:
    with _LOCK:
        return _JOBS.get(job_id)


def _run(job: Job) -> dict:
    job.phase = "running"

    def report(stage: str, done: int | None, total: int | None) -> None:
        job.stage, job.done, job.total = stage, done, total

    try:
        job.package = import_link(job.url, job.folders, LIVE, report)
    except Exception as error:
        job.phase, job.error = "failed", str(error)
        raise
    job.phase = "done"
    return job.package

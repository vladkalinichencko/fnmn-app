"""HTTP boundary of the Mac service. Every request needs the bearer token.

    POST /jobs            {"url", "folders"} -> {"id", ...status}
    GET  /jobs/{id}       phase queued | running | done | failed, stage, done, total, error
    GET  /jobs/{id}/package   the delivery once the job is done
"""

from __future__ import annotations

import os

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

import jobs


class ImportRequest(BaseModel):
    url: str
    folders: list[str] = []


def require_token(authorization: str | None = Header(default=None)) -> None:
    token = os.environ.get("FNMN_TOKEN")
    if not token:
        raise HTTPException(503, "FNMN_TOKEN is not configured")
    if authorization != f"Bearer {token}":
        raise HTTPException(401, "invalid bearer token")


app = FastAPI(title="FNMN Mac service", dependencies=[Depends(require_token)])


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/jobs", status_code=202)
def start_job(request: ImportRequest) -> dict:
    return jobs.submit(request.url, request.folders).status()


@app.get("/jobs/{job_id}")
def job_status(job_id: str) -> dict:
    return _job(job_id).status()


@app.get("/jobs/{job_id}/package")
def job_package(job_id: str) -> dict:
    job = _job(job_id)
    if job.phase != "done":
        raise HTTPException(409, f"job is {job.phase}")
    return job.package


def _job(job_id: str) -> jobs.Job:
    job = jobs.find(job_id)
    if job is None:
        raise HTTPException(404, "no such job")
    return job

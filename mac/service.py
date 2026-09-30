"""HTTP boundary of the Mac service. Every request needs the bearer token.

    POST /jobs            {"url", "folders"} -> {"id", ...status}
    POST /files?name=     the file's bytes as the body -> a job that makes a material of it by its type
    GET  /jobs/{id}       phase queued | running | done | failed, stage, done, total, error
    GET  /jobs/{id}/package   the delivery archive (tar) once the job is done
    POST /videos          {"url"} -> a job that downloads the YouTube video as an mp4
    GET  /jobs/{id}/file  the mp4 once that job is done
    DELETE /jobs/{id}     the phone stored the result: the file and the job go
"""

from __future__ import annotations

import os

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

import jobs


class ImportRequest(BaseModel):
    url: str
    folders: list[str] = []


class VideoRequest(BaseModel):
    url: str


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


@app.post("/files", status_code=202)
async def start_file(request: Request, name: str) -> dict:
    return jobs.submit(name, [], kind="file", upload=await request.body()).status()


@app.get("/jobs/{job_id}")
def job_status(job_id: str) -> dict:
    return _job(job_id).status()


@app.get("/jobs/{job_id}/package")
def job_package(job_id: str) -> FileResponse:
    job = _job(job_id)
    if job.phase != "done" or job.kind == "videoFile" or job.file is None:
        raise HTTPException(409, f"job is {job.phase}")
    return FileResponse(job.file, media_type="application/x-tar", filename=job.file.name)


@app.delete("/jobs/{job_id}", status_code=204)
def forget_job(job_id: str) -> None:
    if jobs.forget(job_id) is None:
        raise HTTPException(404, "no such job")


@app.post("/videos", status_code=202)
def start_video(request: VideoRequest) -> dict:
    return jobs.submit(request.url, [], kind="videoFile").status()


@app.get("/jobs/{job_id}/file")
def job_file(job_id: str) -> FileResponse:
    job = _job(job_id)
    if job.phase != "done" or job.file is None:
        raise HTTPException(409, f"job is {job.phase}")
    return FileResponse(job.file, media_type="video/mp4", filename=job.file.name)


def _job(job_id: str) -> jobs.Job:
    job = jobs.find(job_id)
    if job is None:
        raise HTTPException(404, "no such job")
    return job

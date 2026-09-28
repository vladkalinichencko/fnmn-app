"""Turn one link into an FNMN delivery: find its kind, read it with that kind's adapter, package it."""

from __future__ import annotations

from adapters import article, arxiv, chatgpt, pdf, x, youtube
from package import ImportFailure, Report, package
from sources import NAMES, source_kind
from web import Web

ADAPTERS = {
    "web": article.read,
    "substack": article.read,
    "arxiv": arxiv.read,
    "pdf": pdf.read,
    "x": x.read,
    "chatgpt": chatgpt.read,
    "youtube": youtube.read,
}


def import_link(url: str, folders: list[str], web: Web, report: Report = lambda *_: None) -> dict:
    kind = source_kind(url)
    if kind is None:
        raise ImportFailure("fetchingPage", "link must be an absolute HTTP or HTTPS address")
    if kind not in ADAPTERS:
        raise ImportFailure("saving", f"{NAMES[kind]} is recognized, but the Mac service does not prepare it yet.")
    try:
        content = ADAPTERS[kind](url, web, report)
    except ImportFailure:
        raise
    except ValueError as error:
        raise ImportFailure("saving", str(error)) from error
    except Exception as error:
        raise ImportFailure("fetchingPage", str(error)) from error
    try:
        return package(url, content, folders)
    except ValueError as error:
        raise ImportFailure("saving", str(error)) from error

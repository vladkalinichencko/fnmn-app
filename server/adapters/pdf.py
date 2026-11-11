"""Any PDF through the book pipeline in server/pdf-book.

Every page goes to DeepSeek-OCR-2, the assembler joins that OCR with the PDF
text layer, footnotes and formulas the assembler doubts go back to the model,
the assembler runs again with those answers, and the export checks the result.
The steps run in the pinned `.venv-ocr` environment and take seconds per page.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Callable

import pymupdf

from package import Document, ImportFailure, Report
from web import Web

_PIPELINE = Path(__file__).resolve().parents[1] / "pdf-book"
_PYTHON = Path(__file__).resolve().parents[2] / ".venv-ocr" / "bin" / "python"
_HEADING = re.compile(r"^(#+) (.+)$", re.M)
_OCR = threading.Lock()

sys.path.insert(0, str(_PIPELINE))
from math_issues import formula_jobs


def read(url: str, web: Web, report: Report) -> Document:
    report("fetchingPage", None, None)
    return transcribe(web.bytes(url), None, None, report)


def transcribe(pdf: bytes, title: str | None, authors: str | None, report: Report) -> Document:
    """One PDF at a time: two copies of the OCR model do not fit in memory together."""
    report("waitingForOCR", None, None)
    with _OCR, tempfile.TemporaryDirectory() as work:
        root = Path(work)
        source = root / "document.pdf"
        source.write_bytes(pdf)
        with pymupdf.open(source) as document:
            pages = len(document)
            title = title or (document.metadata.get("title") or "").strip() or None
            authors = authors or (document.metadata.get("author") or "").strip() or None
        ocr, book = root / "ocr", root / "book.md"
        _step(report, "ocr", pages, lambda: _count(ocr, r"page-\d+\.json"), "run-ocr2.py", source, ocr)
        _first_assembly(report, source, ocr, book)
        candidates = json.loads(book.with_suffix(".candidates.json").read_text())
        footnotes = root / "footnote-overrides.json"
        formulas = root / "formula-overrides.json"
        footnote_total = sum(issue["type"] == "footnote_needs_ocr" for page in candidates for issue in page["issues"])
        _step(report, "footnotes", footnote_total, lambda: _count(root / "footnote-ocr", r".+\.json"),
              "run-footnote-ocr.py", book.with_suffix(".candidates.json"), footnotes)
        _step(report, "formulas", len(formula_jobs(candidates)), lambda: _count(root / "formula-ocr", r".+\.json"),
              "run-formula-ocr.py", book.with_suffix(".candidates.json"), formulas)
        _step(report, "assembly", None, None, "assemble-book.py", source, ocr, book,
              "--footnote-overrides", footnotes, "--formula-overrides", formulas)
        heading = _ensure_heading(book, title)
        config = root / "book.json"
        config.write_text(json.dumps({"title": title or heading, "authors": authors or "", "content_start": heading}))
        exported = root / "app"
        _step(report, "export", None, None, "export-app-book.py", book, config, exported)
        files = {f"assets/{path.name}": path.read_bytes() for path in (exported / "assets").iterdir() if path.is_file()}
        return Document((exported / "content.md").read_text(), title or heading, authors, files)


def _first_assembly(report: Report, source: Path, ocr: Path, book: Path) -> None:
    """The first pass may fail validation on exactly the footnotes and formulas the next steps re-read."""
    try:
        _step(report, "assembly", None, None, "assemble-book.py", source, ocr, book)
    except ImportFailure:
        if not book.with_suffix(".candidates.json").exists():
            raise


def _step(report: Report, stage: str, total: int | None, done: Callable[[], int] | None, script: str, *args: Path | str) -> None:
    if total == 0:
        return
    report(stage, 0 if total else None, total)
    process = subprocess.Popen([str(_PYTHON), str(_PIPELINE / script), *map(str, args)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    while process.poll() is None:
        if done is not None:
            report(stage, done(), total)
        time.sleep(2)
    _, error = process.communicate()
    if process.returncode != 0:
        raise ImportFailure(stage, error.strip().splitlines()[-1] if error.strip() else f"{script} failed")
    report(stage, total, total)


def _count(directory: Path, pattern: str) -> int:
    if not directory.exists():
        return 0
    return sum(bool(re.fullmatch(pattern, path.name)) for path in directory.iterdir())


def _ensure_heading(book: Path, title: str | None) -> str:
    text = book.read_text()
    match = _HEADING.search(text)
    if match:
        return match.group(2).strip()
    heading = title or "Document"
    book.write_text(f"# {heading}\n\n{text}")
    return heading

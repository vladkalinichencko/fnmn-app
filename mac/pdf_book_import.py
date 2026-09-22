"""Read a PDF-only arXiv paper with the book assembler.

The pages given to the assembler are the PDF text layer in the grounded form
that assembler already reads. A scanned page with no text layer stops here.
The neural OCR step is a separate book job and is not part of a link import.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pymupdf

_ROOT = Path(__file__).resolve().parent / "pdf-book"
_HEADING = re.compile(r"^(#+) (.+)$", re.M)


def book_markdown(pdf: bytes, title: str | None, authors: str | None) -> tuple[str, str | None, dict[str, bytes]]:
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        pdf_path = root / "paper.pdf"
        pdf_path.write_bytes(pdf)
        ocr = root / "ocr"
        ocr.mkdir()
        if not _grounded_pages(pdf_path, ocr):
            raise ValueError("arXiv PDF has no text layer for the book pipeline")
        assembled = root / "book.md"
        _run(_ROOT / "assemble-book.py", pdf_path, ocr, assembled)
        heading = _ensure_heading(assembled, title)
        exported = root / "book"
        config = root / "book.json"
        config.write_text(json.dumps({
            "title": title or heading,
            "authors": authors or "",
            "content_start": heading,
        }))
        _run(_ROOT / "export-app-book.py", assembled, config, exported)
        markdown = (exported / "content.md").read_text()
        if title and not any(line.startswith("# ") for line in markdown.splitlines()):
            markdown = f"# {title}\n\n{markdown}"
        files = {
            f"assets/{path.name}": path.read_bytes()
            for path in (exported / "assets").iterdir()
            if path.is_file()
        }
        return markdown, authors, files


def _grounded_pages(pdf_path: Path, ocr: Path) -> bool:
    found = False
    with pymupdf.open(pdf_path) as document:
        for number, page in enumerate(document, 1):
            chunks = []
            for block in page.get_text("dict")["blocks"]:
                kind, text = _block(block)
                if kind is None:
                    continue
                box = _box(block["bbox"], page.rect)
                chunks.append(f"<|ref|>{kind}<|/ref|><|det|>[{box}]<|/det|>\n{text}\n")
                found = True
            (ocr / f"page-{number}.md").write_text("".join(chunks))
            (ocr / f"page-{number}.json").write_text(json.dumps({"finish_reason": "stop"}))
    return found


def _block(block: dict) -> tuple[str | None, str]:
    if block.get("type") == 1:
        return "image", ""
    if block.get("type") != 0:
        return None, ""
    spans = [span for line in block.get("lines", []) for span in line.get("spans", [])]
    text = " ".join(span.get("text", "") for span in spans).strip()
    if not text:
        return None, ""
    size = max((span.get("size", 0) for span in spans), default=0)
    return ("title" if size >= 14 else "text"), text


def _box(bbox: list, rect) -> list[int]:
    x0, y0, x1, y1 = bbox
    width = rect.width or 1
    height = rect.height or 1
    return [round(x0 / width * 1000), round(y0 / height * 1000), round(x1 / width * 1000), round(y1 / height * 1000)]


def _ensure_heading(path: Path, title: str | None) -> str:
    text = path.read_text()
    match = _HEADING.search(text)
    if match:
        return match.group(2).strip()
    heading = title or "Paper"
    path.write_text(f"# {heading}\n\n{text}")
    return heading


def _run(script: Path, *args: Path) -> None:
    completed = subprocess.run([sys.executable, str(script), *(str(arg) for arg in args)], capture_output=True, text=True)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        raise ValueError(detail or f"{script.name} failed")

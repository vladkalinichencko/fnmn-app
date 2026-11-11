"""A file sent from the phone, read by its type.

A PDF goes through the PDF pipeline, Markdown and plain text are already the
text, and an HTML page is read like a web page, keeping the pictures it names
by an absolute address. A file of any other type has nothing to read, and
`read` says so; the job then keeps the file itself as the material.
"""

from __future__ import annotations

from pathlib import Path
from urllib.parse import quote

from adapters import article, pdf
from adapters.html_markdown import article_markdown
from package import Document, ImportFailure, Report
from web import Web

TEXT = {".md", ".markdown", ".txt"}
PAGES = {".html", ".htm"}


def read(name: str, data: bytes, web: Web, report: Report) -> Document:
    suffix = Path(name).suffix.lower()
    if suffix == ".pdf":
        return pdf.transcribe(data, None, None, report)
    if suffix in TEXT:
        return Document(_text(data), None)
    if suffix in PAGES:
        source = _text(data)
        markdown, assets = article_markdown(source, f"file:///{quote(name)}")
        return article.document(source, markdown, assets, web, report)
    raise ImportFailure("saving", f"the server does not read {suffix or 'these'} files, so the file is kept as it is")


def _text(data: bytes) -> str:
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ImportFailure("saving", "the file is not UTF-8 text") from error

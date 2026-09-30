from __future__ import annotations

from urllib.parse import urlparse

NAMES = {
    "web": "Web",
    "arxiv": "arXiv",
    "youtube": "YouTube",
    "x": "X",
    "substack": "Substack",
    "chatgpt": "ChatGPT",
    "pdf": "PDF",
    "notebook": "Jupyter notebook",
}


def source_kind(url: str) -> str | None:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        return None
    host = (parsed.hostname or "").lower()
    if not host:
        return None
    if host == "youtu.be" or host == "youtube.com" or host.endswith(".youtube.com"):
        return "youtube"
    if host == "arxiv.org" or host.endswith(".arxiv.org"):
        return "arxiv"
    if host in {"x.com", "twitter.com"} or host.endswith(".x.com") or host.endswith(".twitter.com"):
        return "x"
    if host == "substack.com" or host.endswith(".substack.com"):
        return "substack"
    if host == "chatgpt.com" or host.endswith(".chatgpt.com") or host == "chat.openai.com":
        return "chatgpt"
    if parsed.path.lower().endswith(".pdf"):
        return "pdf"
    if parsed.path.lower().endswith(".ipynb"):
        return "notebook"
    return "web"

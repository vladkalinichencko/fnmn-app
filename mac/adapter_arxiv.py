from __future__ import annotations

import gzip
import hashlib
import io
import re
import tarfile
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote, urlparse

_PAPER = re.compile(
    r"/(?:abs|pdf|html|src|e-print)/"
    r"((?:[a-zA-Z\-]+(?:\.[A-Za-z]+)?)?/?)"
    r"((?:\d{4}\.\d{4,5}|\d{7})(?:v\d+)?)"
    r"(?:\.pdf)?/?$"
)
_ATOM = {"a": "http://www.w3.org/2005/Atom"}
_INPUT = re.compile(r"\\(?:input|include)\{([^{}]+)\}")
_HEADING = re.compile(r"\\(section|subsection|subsubsection)\*?\{([^{}]*)\}")
_GRAPHICS = re.compile(r"\\includegraphics(?:\[[^]]*\])?\{([^{}]+)\}")
_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
_NO_SOURCE = "arXiv has no LaTeX source; the PDF has to go through the book pipeline"


def arxiv_markdown(url: str, fetch_text, fetch_bytes) -> tuple[str, str | None, dict[str, bytes]]:
    paper = paper_id(url)
    if paper is None:
        raise ValueError("arXiv address has no paper id")
    title, authors = _metadata(fetch_text, paper)
    texts, images = unpack_source(fetch_bytes(f"https://export.arxiv.org/e-print/{quote(paper, safe='/')}"))
    return render_tex(texts, images, title, authors)


def paper_id(url: str) -> str | None:
    match = _PAPER.search(urlparse(url).path)
    if match is None:
        return None
    return f"{match.group(1)}{match.group(2)}"


def unpack_source(data: bytes) -> tuple[dict[str, str], dict[str, bytes]]:
    if data.startswith(b"%PDF"):
        raise ValueError(_NO_SOURCE)
    if len(data) > 40_000_000:
        raise ValueError("arXiv source is larger than the importer accepts")
    texts, images = _from_tar(data)
    if texts:
        return texts, images
    payload = _gunzip(data)
    if payload.startswith(b"%PDF"):
        raise ValueError(_NO_SOURCE)
    if b"\\documentclass" in payload[:8000] or payload.lstrip().startswith(b"\\"):
        return {"main.tex": payload.decode("utf-8", errors="replace")}, {}
    raise ValueError("arXiv source is not a TeX archive")


def render_tex(
    texts: dict[str, str],
    images: dict[str, bytes],
    title: str | None,
    authors: str | None,
) -> tuple[str, str | None, dict[str, bytes]]:
    main = _main_tex(texts)
    expanded = _expand(main, texts, set(), 0)
    body = _document_body(expanded)
    heading = _plain(title or _command(expanded, "title") or "arXiv paper")
    if not heading:
        raise ValueError("arXiv source has no title")
    files: dict[str, bytes] = {}
    markdown = _markdown_body(body, images, files, main)
    if not markdown.strip():
        raise ValueError("arXiv source has no readable text")
    text = f"# {heading}\n\n"
    if authors:
        text += authors.strip() + "\n\n"
    text += markdown.strip() + "\n"
    return text, authors, files


def _metadata(fetch_text, paper: str) -> tuple[str | None, str | None]:
    try:
        payload = fetch_text(
            "https://export.arxiv.org/api/query?id_list=" + quote(paper, safe="/")
        )
    except Exception:
        return None, None
    try:
        root = ET.fromstring(payload)
    except ET.ParseError:
        return None, None
    title = root.findtext("a:entry/a:title", default="", namespaces=_ATOM)
    names = [
        node.text.strip()
        for node in root.findall("a:entry/a:author/a:name", _ATOM)
        if node.text and node.text.strip()
    ]
    return (_plain(title) or None), (", ".join(names) or None)


def _from_tar(data: bytes) -> tuple[dict[str, str], dict[str, bytes]]:
    texts: dict[str, str] = {}
    images: dict[str, bytes] = {}
    try:
        archive = tarfile.open(fileobj=io.BytesIO(data), mode="r:*")
    except tarfile.TarError:
        return texts, images
    with archive:
        count = 0
        for member in archive:
            if not member.isfile():
                continue
            count += 1
            if count > 400:
                raise ValueError("arXiv source has too many files")
            name = _safe_name(member.name)
            if name is None:
                continue
            extracted = archive.extractfile(member)
            if extracted is None:
                continue
            _store(name, extracted.read(8_000_000), texts, images)
    return texts, images


def _gunzip(data: bytes) -> bytes:
    if data[:2] != b"\x1f\x8b":
        return data
    try:
        return gzip.decompress(data)
    except OSError:
        return data


def _store(name: str, blob: bytes, texts: dict[str, str], images: dict[str, bytes]) -> None:
    suffix = Path(name).suffix.lower()
    if suffix == ".tex":
        texts[name] = blob.decode("utf-8", errors="replace")
    elif suffix in _IMAGE_SUFFIXES:
        images[name] = blob


def _safe_name(name: str) -> str | None:
    path = Path(name)
    if path.is_absolute() or ".." in path.parts:
        return None
    return path.as_posix()


def _main_tex(texts: dict[str, str]) -> str:
    candidates = [name for name, body in texts.items() if "\\documentclass" in body]
    if not candidates and len(texts) == 1:
        return next(iter(texts))
    if not candidates:
        raise ValueError("arXiv source has no main TeX file")
    candidates.sort(key=lambda name: (name.count("/"), -len(texts[name])))
    return candidates[0]


def _expand(name: str, texts: dict[str, str], seen: set[str], depth: int) -> str:
    if depth > 20 or name in seen:
        return ""
    seen.add(name)
    body = _strip_comments(texts[name])

    def include(match: re.Match[str]) -> str:
        target = _resolve(name, match.group(1), texts)
        if target is None:
            return match.group(0)
        return _expand(target, texts, seen, depth + 1)

    return _INPUT.sub(include, body)


def _resolve(base: str, target: str, texts: dict[str, str]) -> str | None:
    raw = target.strip()
    folder = Path(base).parent
    options = [raw]
    if str(folder) not in {"", "."}:
        options.insert(0, f"{folder.as_posix()}/{raw}")
    for option in options:
        for candidate in (option, f"{option}.tex"):
            if candidate in texts:
                return candidate
            for key in texts:
                if key.endswith("/" + candidate):
                    return key
    return None


def _document_body(tex: str) -> str:
    match = re.search(r"\\begin\{document\}(.*)\\end\{document\}", tex, re.S)
    return match.group(1) if match else tex


def _markdown_body(tex: str, images: dict[str, bytes], files: dict[str, bytes], main: str) -> str:
    body = _strip_comments(tex)
    body = re.sub(r"\\(?:title|author|date|thanks)\{([^{}]*)\}", "", body)
    body = re.sub(r"\\(?:maketitle|tableofcontents)\b", "", body)
    body = re.sub(r"\\(?:begin|end)\{abstract\}", "\n\n", body)
    body = re.sub(r"\\begin\{(?:figure|table)\*?\}(?:\[[^]]*\])?", "", body)
    body = re.sub(r"\\end\{(?:figure|table)\*?\}", "", body)
    body = re.sub(r"\\caption\{([^{}]*)\}", r"\n\n\1\n\n", body)
    body = re.sub(r"\\label\{[^{}]*\}", "", body)
    body = _HEADING.sub(lambda match: _heading(match.group(1), match.group(2)), body)
    body = re.sub(r"\\begin\{(?:equation|align|gather)\*?\}", "\n\n$$", body)
    body = re.sub(r"\\end\{(?:equation|align|gather)\*?\}", "$$\n\n", body)
    body = body.replace(r"\[", "\n\n$$").replace(r"\]", "$$\n\n")
    body = body.replace(r"\(", "$").replace(r"\)", "$")
    body = _GRAPHICS.sub(lambda match: _graphic(match.group(1), images, files, main), body)
    for _ in range(4):
        body = re.sub(r"\\(?:footnote|emph|textbf|textit|textrm|texttt)\{([^{}]*)\}", r"\1", body)
    body = re.sub(r"\\(?:cite|ref)\{([^{}]*)\}", r"[\1]", body)
    return re.sub(r"\n{3,}", "\n\n", body).strip()


def _heading(kind: str, text: str) -> str:
    marks = {"section": "##", "subsection": "###", "subsubsection": "####"}
    return f"\n\n{marks[kind]} {_plain(text)}\n\n"


def _graphic(target: str, images: dict[str, bytes], files: dict[str, bytes], main: str) -> str:
    found = _find_image(target.strip(), images, main)
    if found is None:
        return f"\\includegraphics{{{target}}}"
    name, blob = found
    suffix = Path(name).suffix.lower()
    path = f"assets/{hashlib.sha256(name.encode()).hexdigest()[:16]}{suffix}"
    files[path] = blob
    return f"\n\n![{Path(name).stem}]({path})\n\n"


def _find_image(target: str, images: dict[str, bytes], main: str) -> tuple[str, bytes] | None:
    folder = Path(main).parent
    options = [target]
    if str(folder) not in {"", "."}:
        options.insert(0, f"{folder.as_posix()}/{target}")
    for option in options:
        candidates = [option] if Path(option).suffix else [f"{option}{suffix}" for suffix in sorted(_IMAGE_SUFFIXES)]
        for candidate in candidates:
            if candidate in images:
                return candidate, images[candidate]
            for key, blob in images.items():
                if key.endswith("/" + candidate):
                    return key, blob
    return None


def _strip_comments(tex: str) -> str:
    lines = []
    for line in tex.splitlines():
        kept = []
        index = 0
        while index < len(line):
            if line[index] == "\\" and index + 1 < len(line):
                kept.append(line[index : index + 2])
                index += 2
                continue
            if line[index] == "%":
                break
            kept.append(line[index])
            index += 1
        lines.append("".join(kept).rstrip())
    return "\n".join(lines)


def _command(tex: str, name: str) -> str | None:
    match = re.search(r"\\" + re.escape(name) + r"\{([^{}]*)\}", tex)
    return match.group(1).strip() if match else None


def _plain(text: str) -> str:
    cleaned = re.sub(r"\\[a-zA-Z]+\{([^{}]*)\}", r"\1", text or "")
    return " ".join(cleaned.split())

from __future__ import annotations

import json
import re
from html import unescape
from urllib.parse import urlparse

from adapters.chatgpt import normalize_copied_math
from adapters.conversation import turn
from package import Document, ImportFailure, Report, asset_path
from web import Web

_SHARE = re.compile(r"/share/([0-9A-Fa-f-]{36})")
_SNAPSHOT = "https://claude.ai/api/chat_snapshots/{}?rendering_mode=messages&render_all_tools=true"
_PRE = re.compile(r"<pre[^>]*>([\s\S]*?)</pre>", re.I)
_SENDERS = {"human", "assistant"}
_FENCE = re.compile(r"(```[\s\S]*?```)")
_HEADING = re.compile(r"^(#{1,4}) ", re.M)
_LANGUAGES = {"application/vnd.ant.mermaid": "mermaid", "application/vnd.ant.react": "jsx"}

_PAGE = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { color-scheme: light dark; }
html, body { margin: 0; background: transparent; font: 16px/1.4 -apple-system, system-ui, sans-serif; }
body { padding: 16px; }
svg { max-width: 100%; height: auto; }
</style>
</head>
<body>
{content}
</body>
</html>
"""


def read(url: str, web: Web, report: Report) -> Document:
    report("fetchingPage", None, None)
    match = _SHARE.search(urlparse(url).path)
    if match is None:
        raise ValueError("Claude link is not a public share")
    payload = _conversation(_SNAPSHOT.format(match.group(1)), web)
    title = (payload.get("snapshot_name") or "").strip() or "Claude"
    files: dict[str, bytes] = {}
    artifacts: dict[str, dict] = {}
    parts = [text for message in payload["chat_messages"] if (text := _visible(message, artifacts, files))]
    if not parts:
        raise ValueError("Claude share has no messages")
    return Document(f"# {title}\n\n" + "\n\n".join(parts) + "\n", title, "Claude", files=files)


def _conversation(url: str, web: Web) -> dict:
    """Ask the API the share page itself asks. Cloudflare answers a plain server request with a bot check, so
    when that fails Chrome opens the same address and shows the JSON inside its <pre>."""
    try:
        if (payload := _snapshot(web.text(url))) is not None:
            return payload
        refusal = "no conversation in the answer"
    except Exception as error:
        refusal = str(error)
    try:
        shown = _PRE.search(web.rendered(url))
    except Exception as error:
        raise ImportFailure("fetchingPage", f"{refusal}; Chrome: {error}") from error
    if shown is None or (payload := _snapshot(unescape(shown.group(1)))) is None:
        raise ImportFailure("fetchingPage", f"{refusal}; Chrome: no conversation on the page")
    return payload


def _snapshot(raw: str) -> dict | None:
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if isinstance(parsed, dict) and isinstance(parsed.get("chat_messages"), list):
        return parsed
    return None


def _visible(message, artifacts: dict[str, dict], files: dict[str, bytes]) -> str | None:
    if not isinstance(message, dict) or message.get("sender") not in _SENDERS:
        return None
    blocks = message.get("content")
    if isinstance(blocks, list) and blocks:
        pieces = [_block(block, artifacts, files) for block in blocks if isinstance(block, dict)]
    else:
        pieces = [normalize_copied_math(message.get("text") or "")]
    body = "\n\n".join(piece.strip() for piece in pieces if piece and piece.strip())
    if not body:
        return None
    return turn(message["sender"], body)


def _block(block: dict, artifacts: dict[str, dict], files: dict[str, bytes]) -> str | None:
    """Text and artifacts are what the reader sees in Claude; thinking, tool calls and their results are plumbing."""
    if block.get("type") == "text":
        return normalize_copied_math(block.get("text") or "")
    if block.get("type") == "tool_use" and block.get("name") == "artifacts":
        return _artifact(block.get("input") or {}, artifacts, files)
    return None


def _artifact(spec: dict, artifacts: dict[str, dict], files: dict[str, bytes]) -> str | None:
    """Each create, rewrite or update shows the artifact as it stands after that command, as Claude's card does."""
    artifact = artifacts.setdefault(str(spec.get("id") or ""), {})
    if spec.get("command") == "update":
        old, new = spec.get("old_str"), spec.get("new_str")
        if isinstance(old, str) and isinstance(new, str):
            artifact["content"] = (artifact.get("content") or "").replace(old, new, 1)
    else:
        artifact.update({key: spec[key] for key in ("type", "language", "content") if spec.get(key)})
    content = artifact.get("content")
    if not isinstance(content, str) or not content.strip():
        return None
    kind = artifact.get("type")
    if kind == "text/markdown":
        return "".join(part if part.startswith("```") else _HEADING.sub(r"##\1 ", part) for part in _FENCE.split(normalize_copied_math(content)))
    if kind in {"text/html", "image/svg+xml"}:
        return _page(content, files)
    return _fenced(content, _LANGUAGES.get(kind) or artifact.get("language") or "")


def _page(content: str, files: dict[str, bytes]) -> str:
    whole = content.lstrip()[:15].lower().startswith(("<!doctype", "<html"))
    path = asset_path(content, ".html", "interactive-")
    files[path] = (content if whole else _PAGE.replace("{content}", content)).encode()
    return f"```fnmn-interactive\n{path}\n```"


def _fenced(content: str, language: str) -> str:
    ticks = "`" * max(3, max((len(run) for run in re.findall(r"`+", content)), default=0) + 1)
    return f"{ticks}{language}\n{content.rstrip()}\n{ticks}"

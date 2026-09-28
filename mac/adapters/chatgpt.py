from __future__ import annotations

import json
import re
from urllib.parse import urlparse

from package import Document, Report
from web import Web

_SHARE = re.compile(r"/share/([A-Za-z0-9-]+)")
_LABELS = {"user": "User", "assistant": "Assistant"}
_CITE = re.compile("\ue200cite\ue202.*?\ue201")
_WIKI = re.compile(r"\[\[([^\[\]]+)\]\]")
_DISPLAY = re.compile(r"\\\[(.*?)\\\]", re.S)
_INLINE = re.compile(r"\\\((.+?)\\\)")
_FENCE = re.compile(r"(```[\s\S]*?```)")


def read(url: str, web: Web, report: Report) -> Document:
    report("fetchingPage", None, None)
    match = _SHARE.search(urlparse(url).path)
    if match is None:
        raise ValueError("ChatGPT link is not a public share")
    payload = _conversation(web.text(url))
    if payload is None:
        payload = _conversation(web.text(f"https://chatgpt.com/backend-api/share/{match.group(1)}"))
    if payload is None:
        raise ValueError("ChatGPT did not return the conversation")
    title = (payload.get("title") or "").strip() or "ChatGPT"
    parts = [text for message in _messages(payload) if (text := _visible(message))]
    if not parts:
        raise ValueError("ChatGPT share has no messages")
    return Document(f"# {title}\n\n" + "\n\n".join(parts) + "\n", title, "ChatGPT")


def normalize_copied_math(text: str) -> str:
    return "".join(part if part.startswith("```") else _normalize_chunk(part) for part in _FENCE.split(text))


def _conversation(raw: str) -> dict | None:
    stripped = raw.lstrip()
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = None
        if isinstance(parsed, dict) and (parsed.get("linear_conversation") or parsed.get("mapping")):
            return parsed
    values = _enqueue_values(raw)
    if values is None:
        return None
    data = _share_data(_hydrate(values))
    if isinstance(data, dict) and (data.get("linear_conversation") or data.get("mapping")):
        return data
    return None


def _messages(payload: dict) -> list:
    linear = payload.get("linear_conversation")
    if isinstance(linear, list) and linear:
        return [item.get("message") or item for item in linear if isinstance(item, dict)]
    mapping = payload.get("mapping") or {}
    current = payload.get("current_node")
    chain = []
    seen: set[str] = set()
    while isinstance(current, str) and current not in seen and current in mapping:
        seen.add(current)
        node = mapping[current] or {}
        chain.append(node.get("message"))
        current = node.get("parent")
    chain.reverse()
    return [message for message in chain if message]


def _visible(message) -> str | None:
    if not isinstance(message, dict):
        return None
    author = ((message.get("author") or {}).get("role") or "").strip()
    if author in {"system", "tool"}:
        return None
    metadata = message.get("metadata") or {}
    if metadata.get("is_visually_hidden_from_conversation"):
        return None
    content = message.get("content") or {}
    if content.get("content_type") not in {None, "text", "multimodal_text"}:
        return None
    texts = [part.strip() for part in content.get("parts") or [] if isinstance(part, str) and part.strip()]
    if not texts:
        return None
    label = _LABELS.get(author, author or "Message")
    body = normalize_copied_math("\n\n".join(texts)).strip()
    if not body:
        return None
    return f"## {label}\n\n{body}"


def _normalize_chunk(text: str) -> str:
    text = _CITE.sub("", text)
    text = _WIKI.sub(_wiki_label, text)
    pieces: list[str] = []
    cursor = 0
    for match in _DISPLAY.finditer(text):
        pieces.append(_inline(text[cursor : match.start()]))
        body = match.group(1).strip("\n")
        pieces.append(f"\n\n$$\n{body}\n$$\n\n" if body else "")
        cursor = match.end()
    pieces.append(_inline(text[cursor:]))
    return re.sub(r"\n{3,}", "\n\n", "".join(pieces))


def _wiki_label(match: re.Match[str]) -> str:
    inner = match.group(1)
    if "|" not in inner:
        return match.group(0)
    return inner.split("|", 1)[1]


def _inline(text: str) -> str:
    return _INLINE.sub(lambda match: f"${match.group(1)}$", text)


def _enqueue_values(raw: str) -> list | None:
    key = "streamController.enqueue("
    start = raw.find(key)
    if start < 0:
        return None
    opening = start + len(key)
    if opening >= len(raw) or raw[opening] != '"':
        return None
    cursor = opening + 1
    while cursor < len(raw):
        if raw[cursor] == "\\":
            cursor += 2
            continue
        if raw[cursor] == '"':
            break
        cursor += 1
    try:
        encoded = json.loads(raw[opening : cursor + 1])
        values = json.loads(encoded)
    except (json.JSONDecodeError, TypeError):
        return None
    return values if isinstance(values, list) else None


def _hydrate(values: list):
    hydrated: dict[int, object] = {}

    def walk(index: int):
        if index < 0 or index >= len(values):
            return None
        if index in hydrated:
            return hydrated[index]
        value = values[index]
        if isinstance(value, list):
            out: list = []
            hydrated[index] = out
            out.extend(walk(item) if isinstance(item, int) else item for item in value)
            return out
        if isinstance(value, dict):
            out_dict: dict = {}
            hydrated[index] = out_dict
            for raw_key, raw_val in value.items():
                if isinstance(raw_key, str) and raw_key.startswith("_") and raw_key[1:].lstrip("-").isdigit():
                    real_key = walk(int(raw_key[1:]))
                else:
                    real_key = raw_key
                if not isinstance(real_key, str):
                    continue
                out_dict[real_key] = walk(raw_val) if isinstance(raw_val, int) else raw_val
            return out_dict
        hydrated[index] = value
        return value

    return walk(0)


def _share_data(root) -> dict | None:
    if not isinstance(root, dict):
        return None
    loader = root.get("loaderData")
    if isinstance(loader, dict):
        for key, value in loader.items():
            if "share" not in key or not isinstance(value, dict):
                continue
            server = value.get("serverResponse")
            data = server.get("data") if isinstance(server, dict) else None
            if isinstance(data, dict):
                return data
    return root

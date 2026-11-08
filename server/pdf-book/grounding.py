"""The grounding blocks DeepSeek-OCR wraps each region in: its kind, its box, and the text that follows."""

from __future__ import annotations

import json
import re

MARKER = re.compile(r"<\|ref\|>.*?<\|/ref\|><\|det\|>.*?<\|/det\|>\s*", re.S)
BLOCK = re.compile(r"<\|ref\|>(.*?)<\|/ref\|><\|det\|>(.*?)<\|/det\|>\s*", re.S)


def strip(text: str) -> str:
    """The text of every grounded region, in order, without its markers."""
    matches = list(MARKER.finditer(text))
    if not matches:
        return text.strip()
    return "\n\n".join(
        text[match.end():matches[i + 1].start() if i + 1 < len(matches) else len(text)].strip()
        for i, match in enumerate(matches)
    ).strip()


def blocks(text: str) -> list[dict]:
    """Every grounded region: its kind, its box, and the text that follows it."""
    matches = list(BLOCK.finditer(text))
    if (text[: matches[0].start()] if matches else text).strip():
        raise ValueError("OCR text outside grounding blocks")
    return [
        {
            "kind": match[1],
            "bbox": json.loads(match[2])[0],
            "text": text[match.end(): matches[i + 1].start() if i + 1 < len(matches) else len(text)].strip(),
        }
        for i, match in enumerate(matches)
    ]

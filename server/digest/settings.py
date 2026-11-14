"""The digest settings the app writes as `digest-settings.json` into the FNMN folder.

The file is the one channel between the phone and the Mac: the app owns the words, the
monitor and the builder read them. A missing file means the defaults — the digest runs,
reads only the followed sources, and ships every post it collected.
"""

from __future__ import annotations

import json
from pathlib import Path

FNMN = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/FNMN"
NAME = "digest-settings.json"
DEFAULT_HOURS = (8, 20)
DEFAULT_THRESHOLD = 0.5
DEFAULT_LIMIT = 40
RECOMMENDATION_NETWORKS = ("x", "instagram")


def load(folder: Path | None = None) -> dict:
    """The settings with every default filled in; a torn or foreign file reads as defaults."""
    settings = {
        "enabled": True,
        "hours": list(DEFAULT_HOURS),
        "threshold": DEFAULT_THRESHOLD,
        "limit": DEFAULT_LIMIT,
        "rotation": {},
        "networks": {},
        "sources": {},
    }
    path = (folder or FNMN) / NAME
    if path.exists():
        try:
            stored = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            stored = {}
        if isinstance(stored, dict):
            settings.update({key: value for key, value in stored.items() if key in settings})
            for key in ("networks", "sources"):
                if isinstance(stored.get(key), dict):
                    settings[key] = stored[key]
    return settings


def hours(settings: dict) -> tuple[int, ...]:
    values = settings.get("hours") or []
    return tuple(hour for hour in values if isinstance(hour, int) and 0 <= hour <= 23) or DEFAULT_HOURS


def topics(settings: dict, network: str, source: str) -> list[str]:
    """The keyword topics a post of this network and source is scored against: the network's
    words plus the source's own."""
    found: list[str] = []
    for entry in (settings.get("networks", {}).get(network) or {}, settings.get("sources", {}).get(source) or {}):
        words = entry.get("topics") if isinstance(entry, dict) else None
        for word in words or []:
            if isinstance(word, str) and word.strip() and word.strip() not in found:
                found.append(word.strip())
    return found


def any_topics(settings: dict) -> bool:
    networks = settings.get("networks", {})
    sources = settings.get("sources", {})
    return any(
        isinstance(entry, dict) and entry.get("topics")
        for entry in list(networks.values()) + list(sources.values())
    )


def network_limit(settings: dict, network: str) -> int | None:
    """A per-network ceiling on one delivery's posts; `None` when the network has none."""
    entry = settings.get("networks", {}).get(network)
    limit = entry.get("limit") if isinstance(entry, dict) else None
    return limit if isinstance(limit, int) and limit > 0 else None


def recommendations(settings: dict, network: str) -> bool:
    """Whether the monitor adds the network's recommendation feed beside the followed sources."""
    if network not in RECOMMENDATION_NETWORKS:
        return False
    entry = settings.get("networks", {}).get(network)
    return isinstance(entry, dict) and entry.get("recommendations") is True

"""The subscription list the monitor and the builder all read."""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT = HERE / "subscriptions.json"


def load(path: Path | None = None) -> dict:
    return json.loads((path or DEFAULT).read_text(encoding="utf-8"))

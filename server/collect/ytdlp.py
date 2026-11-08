"""The one yt-dlp call: the command, its JSON output, and its last error line."""

from __future__ import annotations

import json
import shutil
import subprocess

MISSING = "yt-dlp not found on PATH (pip install -r server/requirements.txt)"


def auth(cookies_from_browser: str | None, cookies_file: str | None) -> list[str]:
    """The flags that let yt-dlp read a logged-in library."""
    flags: list[str] = []
    if cookies_from_browser:
        flags += ["--cookies-from-browser", cookies_from_browser]
    if cookies_file:
        flags += ["--cookies", cookies_file]
    return flags


def command(
    url: str,
    *,
    dump: str = "--dump-json",
    flat: bool = True,
    cookies_from_browser: str | None = None,
    cookies_file: str | None = None,
    extra: list[str] | None = None,
) -> list[str]:
    args = ["yt-dlp"]
    if flat:
        args += ["--flat-playlist", "--skip-download"]
    args += [dump, "--no-warnings", *(extra or []), *auth(cookies_from_browser, cookies_file), url]
    return args


def run(args: list[str]) -> str:
    """The command's stdout; a failure is its last error line."""
    if shutil.which("yt-dlp") is None:
        raise RuntimeError(MISSING)
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(last_line(result.stderr) or "yt-dlp failed")
    return result.stdout


def entries(url: str, **options) -> list[dict]:
    """The entries of a playlist or a feed, one JSON object per line."""
    return parse_entries(run(command(url, **options)))


def parse_entries(text: str) -> list[dict]:
    """The JSON objects in a `--dump-json` stream; a line that is not one is skipped."""
    found = []
    for line in text.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            found.append(value)
    return found


def info(url: str, **options) -> dict:
    """One page's whole description: a playlist with its entries, or a video."""
    value = json.loads(run(command(url, dump="--dump-single-json", **options)))
    if not isinstance(value, dict):
        raise RuntimeError("yt-dlp returned no entry")
    return value


def field(url: str, template: str, **options) -> dict:
    """What a `--print` template names, as JSON."""
    return json.loads(run(command(url, dump="--print", flat=False, extra=[template], **options)))


def last_line(text: str) -> str:
    lines = text.strip().splitlines()
    return lines[-1] if lines else ""

"""List every video URL in a YouTube playlist, defaulting to Watch Later.

Watch Later is private, so YouTube only shows it to a logged-in browser.
This script calls yt-dlp (already in mac/requirements.txt) with your
browser cookies, pages through the whole playlist, and writes one
canonical watch URL per line:

    python3 mac/watchlater_urls.py --cookies-from-browser chrome -o watchlater.txt

That file feeds straight into mac/youtube_prepare.py.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

# Authenticated pseudo-URL: the plain playlist?list=WL address is not
# resolvable ("playlist does not exist") even with valid login cookies.
WATCH_LATER = ":ytwatchlater"


def build_command(url: str, cookies_from_browser: str | None, cookies_file: str | None) -> list[str]:
    command = [
        "yt-dlp",
        "--flat-playlist",
        "--skip-download",
        "--dump-json",
        "--no-warnings",
        url,
    ]
    if cookies_from_browser:
        command[-1:-1] = ["--cookies-from-browser", cookies_from_browser]
    if cookies_file:
        command[-1:-1] = ["--cookies", cookies_file]
    return command


def urls_from_lines(lines) -> list[str]:
    urls: list[str] = []
    seen: set[str] = set()
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        video_id = entry.get("id") if isinstance(entry, dict) else None
        if not isinstance(video_id, str) or not video_id:
            continue
        if video_id in seen:
            continue
        seen.add(video_id)
        urls.append(f"https://www.youtube.com/watch?v={video_id}")
    return urls


def list_playlist(url: str, cookies_from_browser: str | None, cookies_file: str | None) -> list[str]:
    if shutil.which("yt-dlp") is None:
        raise RuntimeError("yt-dlp not found on PATH (pip install -r mac/requirements.txt)")
    command = build_command(url, cookies_from_browser, cookies_file)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert process.stdout is not None
    urls = urls_from_lines(process.stdout)
    _, stderr = process.communicate()
    if process.returncode != 0:
        hint = stderr.strip().splitlines()[-1] if stderr.strip() else "yt-dlp failed"
        if "Sign in" in stderr or "login" in stderr.lower() or not urls:
            hint += "\nWatch Later needs login: pass --cookies-from-browser chrome|safari|firefox or --cookies cookies.txt"
        raise RuntimeError(hint)
    return urls


def main() -> None:
    parser = argparse.ArgumentParser(description="Dump full playlist video URLs, one per line (default: Watch Later).")
    parser.add_argument("--playlist", default=WATCH_LATER, help=f"playlist URL (default: {WATCH_LATER})")
    parser.add_argument("-o", "--output", type=Path, default=None, help="output file (default: stdout)")
    parser.add_argument("--cookies-from-browser", default=None, help="e.g. chrome, safari, firefox, edge")
    parser.add_argument("--cookies", default=None, help="Netscape cookies.txt exported from a logged-in browser")
    args = parser.parse_args()

    urls = list_playlist(args.playlist, args.cookies_from_browser, args.cookies)
    text = "\n".join(urls) + ("\n" if urls else "")
    if args.output is None:
        sys.stdout.write(text)
    else:
        args.output.write_text(text, encoding="utf-8")
    print(f"wrote {len(urls)} urls", file=sys.stderr)


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlparse

from fnmn_service import stable_id


def input_urls(path: Path) -> list[str]:
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text())
        values: list[str] = []

        def visit(value: object) -> None:
            if isinstance(value, dict):
                for key, child in value.items():
                    if key in {"url", "webpage_url"} and isinstance(child, str) and "youtu" in child:
                        values.append(child)
                    else:
                        visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)

        visit(data)
        return list(dict.fromkeys(values))
    return list(dict.fromkeys(line.strip() for line in path.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")))


def prepare(input_path: Path, output_directory: Path, cookies_from_browser: str | None = None) -> int:
    urls = input_urls(input_path)
    if not urls:
        raise ValueError("input contains no YouTube URLs")
    for url in urls:
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or parsed.hostname not in {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}:
            raise ValueError(f"unsupported YouTube URL: {url}")
    with tempfile.NamedTemporaryFile("w", delete=False) as batch:
        batch.write("\n".join(urls))
        batch_path = batch.name
    command = ["yt-dlp", "--batch-file", batch_path, "--flat-playlist", "--dump-json", "--skip-download"]
    if cookies_from_browser:
        command.extend(["--cookies-from-browser", cookies_from_browser])
    process = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    output_directory.mkdir(parents=True, exist_ok=True)
    count = 0
    assert process.stdout is not None
    for line in process.stdout:
        metadata = json.loads(line)
        video_id = metadata.get("id")
        if not video_id:
            continue
        source_url = f"https://www.youtube.com/watch?v={video_id}"
        package = {
            "version": 1,
            "material": {
                "id": f"youtube:{video_id}",
                "kind": "video",
                "title": metadata.get("title") or video_id,
                "sourceURL": source_url,
                "byline": metadata.get("channel") or metadata.get("uploader"),
            },
            "sections": [{"id": "video", "parentID": None, "title": metadata.get("title") or video_id, "level": 1, "firstBlockID": "video"}],
            "blocks": [{
                "id": "video",
                "sectionID": "video",
                "kind": "video",
                "html": "",
                "sourceFragment": None,
                "mediaURL": f"https://www.youtube.com/embed/{video_id}?enablejsapi=1",
                "startSeconds": 0.0,
            }],
            "folders": [input_path.stem],
        }
        (output_directory / f"{stable_id('youtube', video_id).replace(':', '-')}.json").write_text(json.dumps(package, ensure_ascii=False, indent=2))
        count += 1
    if process.wait() != 0:
        raise RuntimeError("yt-dlp failed; no account or cookies were accessed unless --cookies-from-browser was explicitly supplied")
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare FNMN video packages from an explicit YouTube URL list or JSON export")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cookies-from-browser", help="Explicitly allow yt-dlp to read cookies from the selected browser")
    args = parser.parse_args()
    print(f"prepared {prepare(args.input, args.output, args.cookies_from_browser)} videos")


if __name__ == "__main__":
    main()

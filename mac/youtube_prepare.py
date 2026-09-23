from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlparse

from adapter_youtube import youtube_package_live
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
    output_directory.mkdir(parents=True, exist_ok=True)
    count = 0
    for url in urls:
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or parsed.hostname not in {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}:
            raise ValueError(f"unsupported YouTube URL: {url}")
        package = youtube_package_live(url, [input_path.stem], cookies_from_browser=cookies_from_browser)
        video_id = package["material"]["id"].removeprefix("youtube:")
        (output_directory / f"{stable_id('youtube', video_id).replace(':', '-')}.json").write_text(json.dumps(package, ensure_ascii=False, indent=2))
        count += 1
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

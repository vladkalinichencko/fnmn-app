"""Open one network in a windowed Chrome so the reader can log in once; the profile keeps the session and every
later monitor run is headless on it.

    python -m digest.login x
    python -m digest.login instagram
"""

from __future__ import annotations

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

from digest.reading import profile

LOGIN = {
    "x": "https://x.com/login",
    "instagram": "https://www.instagram.com/accounts/login/",
    "telegram": "https://t.me/",
}


def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] not in LOGIN:
        print("usage: python -m digest.login x|instagram|telegram")
        return 2
    network = argv[0]
    folder = profile(network)
    folder.mkdir(parents=True, exist_ok=True)
    print(f"Opening {LOGIN[network]}. Log in, then come back here and press Enter.")
    with sync_playwright() as playwright:
        context = playwright.chromium.launch_persistent_context(
            str(folder), channel="chrome", headless=False, chromium_sandbox=True
        )
        try:
            page = context.pages[0] if context.pages else context.new_page()
            page.goto(LOGIN[network])
            input()
            print(f"The window is on {page.url} — {page.title()}")
            if "/login" in page.url or "/accounts/login" in page.url:
                print("Still on the login page: the profile did not take the session.")
        finally:
            context.close()
    print(f"The {network} profile is kept in {folder}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

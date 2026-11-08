"""Open one network in a normal Chrome window so the reader can log in once.

    python -m digest.login x
    python -m digest.login instagram
    python -m digest.login telegram

The profile under `profiles/<network>/` is the same one the headless monitor uses. The login window is
plain Chrome, not a Playwright browser: X's onboarding check finishes in a normal window but can hang when
the page is driven over the automation protocol.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from digest.reading import profile

LOGIN = {
    "x": "https://x.com/login",
    "instagram": "https://www.instagram.com/accounts/login/",
    "telegram": "https://t.me/",
}
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")


def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] not in LOGIN:
        print("usage: python -m digest.login x|instagram|telegram")
        return 2
    network = argv[0]
    folder = profile(network)
    folder.mkdir(parents=True, exist_ok=True)
    print(f"Opening {LOGIN[network]} in a normal Chrome window.")
    print("Log in, quit Chrome with Cmd-Q, then press Enter here.")
    try:
        process = subprocess.Popen([
            str(CHROME),
            f"--user-data-dir={folder}",
            "--no-first-run",
            "--no-default-browser-check",
            LOGIN[network],
        ])
    except OSError as error:
        print(f"Could not open Chrome: {error}")
        return 1
    input()
    if process.poll() is None:
        print("Chrome is still running; quit it before the monitor uses this profile.")
    print(f"The {network} profile is kept in {folder}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

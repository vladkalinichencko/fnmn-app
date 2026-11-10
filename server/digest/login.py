"""Open one network in a headed Chrome window so the owner can log in once.

The window is real and driven by no one: X and Instagram finish their checks in it, which a job's
headless browser cannot. After the login the browser closes and saves the profile on disk; the next
reader job runs headless on it, invisible.

    python -m digest.login x
    python -m digest.login instagram
    python -m digest.login telegram
"""

from __future__ import annotations

import sys

import reader

LOGIN = {
    "x": "https://x.com/login",
    "instagram": "https://www.instagram.com/accounts/login/",
    "telegram": "https://web.telegram.org/",
}


def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] not in LOGIN:
        print("usage: python -m digest.login x|instagram|telegram")
        return 2
    network = argv[0]
    session = reader.ensure(network, headed=True)
    tab = session.tab()
    tab.goto(LOGIN[network])
    print(f"Opening {LOGIN[network]} in a Chrome window.")
    print("Log in there, then press Enter here.")
    input()
    session.close()
    print(f"The {network} profile is kept in {reader.profile(network)}; the next reader job runs headless on it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

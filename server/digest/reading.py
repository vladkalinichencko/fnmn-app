"""The source contract: every network is one module with the same call.

    collect(source, web, store, folders, report, page=None) -> SourceResult

X, Instagram and Telegram read through `page`, the logged-in browser profile, and raise SourceFailure when the
network refuses the reader. Telegram also reads a channel whose public page is enough through `web`, where no
`page` is passed. `report` names the stage for the monitor log; a source that read only part of its list says
so in `SourceResult.note` instead of pretending the run was complete.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterator

import httpx
from playwright.sync_api import Page, sync_playwright

from digest.store import Post
from web import Web

PROFILES = Path(__file__).resolve().parent / "profiles"


@dataclass
class SourceResult:
    posts: list[Post] = field(default_factory=list)
    name: str | None = None
    note: str | None = None


class SourceFailure(Exception):
    """The network refused the reader; the reason reaches the digest's source status."""

    def __init__(self, reason: str):
        self.reason = reason
        super().__init__(reason)


def profile(network: str) -> Path:
    return PROFILES / network


BROWSER = {"x", "instagram", "telegram"}
"""The networks read through a logged-in profile; Telegram also has a public page."""


def needs_browser(network: str) -> bool:
    return network in BROWSER


@contextmanager
def browser(network: str) -> Iterator[Page]:
    """The logged-in profile of one network, headless, one page. Chrome without a window names itself
    HeadlessChrome, which X and Instagram refuse, so the page introduces itself as the ordinary Chrome it is."""
    with sync_playwright() as playwright:
        launch = {"channel": "chrome", "headless": True, "chromium_sandbox": True}
        agent = playwright.chromium.launch(**launch).new_page().evaluate("navigator.userAgent").replace("HeadlessChrome", "Chrome")
        context = playwright.chromium.launch_persistent_context(
            str(profile(network)),
            channel="chrome",
            headless=True,
            chromium_sandbox=True,
            user_agent=agent,
            viewport={"width": 1280, "height": 1600},
        )
        try:
            yield context.new_page()
        finally:
            context.close()


def save_photo(web: Web, store, post_id: str, index: int | str, url: str, fetch: Callable[[str], bytes] | None = None) -> dict | None:
    """One picture of a post, written under its own name. A picture the network will not serve is left out of
    the post instead of stopping it: the card then shows the text without that picture."""
    try:
        data = fetch(url) if fetch is not None else web.bytes(url)
    except (OSError, httpx.HTTPError):
        return None
    extension = "png" if url.split("?")[0].lower().endswith(".png") else "jpg"
    return store.save_media(post_id, index, data, extension)


def page_fetch(page) -> Callable[[str], bytes]:
    """Downloads through the logged-in page's own request context, so a CDN sees the profile's cookies."""
    def fetch(url: str) -> bytes:
        try:
            response = page.context.request.get(url, timeout=30_000)
        except Exception as error:
            raise OSError(str(error)) from error
        if response.status >= 400:
            raise OSError(f"the picture returned HTTP {response.status}")
        return response.body()
    return fetch

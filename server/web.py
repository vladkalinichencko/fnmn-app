"""Everything the server reads from the internet goes through one Web value.

Adapters receive a Web and never import httpx or Chrome themselves, so tests
pass a Web made of plain functions.
"""

from __future__ import annotations

import re
import threading
from html import escape
from typing import Callable, NamedTuple

import httpx
from playwright.sync_api import Error, sync_playwright

_USER_AGENT = "FNMN/1.0 (https://github.com/vladkalinichencko/fnmn-app) article reader"
_CHROME = threading.Lock()
_SETTLE_MS = 10_000


class Web(NamedTuple):
    text: Callable[[str], str]
    bytes: Callable[[str], bytes]
    page: Callable[[str], str]
    rendered: Callable[[str], str]


def _get(url: str) -> httpx.Response:
    response = httpx.get(url, follow_redirects=True, timeout=30, headers={"User-Agent": _USER_AGENT})
    response.raise_for_status()
    return response


def _page(url: str) -> str:
    response = _get(url)
    return with_base(response.text, str(response.url))


def _rendered(url: str) -> str:
    """Open the page in Google Chrome without a window, one page at a time.

    Chrome without a window names itself HeadlessChrome and reports automation, and Medium refuses such a
    browser, so it introduces itself as the ordinary Chrome it is.
    """
    with _CHROME, sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            channel="chrome",
            headless=True,
            args=["--disable-blink-features=AutomationControlled"],
        )
        try:
            probe = browser.new_page()
            agent = probe.evaluate("navigator.userAgent").replace("HeadlessChrome", "Chrome")
            probe.close()
            page = browser.new_page(user_agent=agent, viewport={"width": 1280, "height": 1600})
            documents = []
            page.on("response", lambda response: documents.append(response)
                    if response.request.is_navigation_request() and response.frame == page.main_frame else None)
            # A page whose trackers or widgets never finish loading is still read once its document is there.
            page.goto(url, wait_until="domcontentloaded", timeout=45_000)
            for state in ("load", "networkidle"):
                try:
                    page.wait_for_load_state(state, timeout=_SETTLE_MS)
                except Error:
                    pass
            _wait_for_text(page)
            if documents and documents[-1].status >= 400:
                raise OSError(f"browser got HTTP {documents[-1].status} for {url}")
            for _ in range(3):
                try:
                    return with_base(page.evaluate("document.documentElement.outerHTML"), page.url)
                except Error:
                    page.wait_for_load_state("load", timeout=15_000)
            raise OSError(f"page kept navigating: {url}")
        finally:
            browser.close()


def _wait_for_text(page) -> None:
    """A page that draws its article from script keeps growing after the network calms down, so read it once its text has stood still for three seconds."""
    lengths = []
    for _ in range(2 * _SETTLE_MS // 500):
        try:
            lengths.append(page.evaluate("document.body ? document.body.innerText.length : 0"))
        except Error:
            lengths.append(-1)
        if len(lengths) > 6 and len(set(lengths[-7:])) == 1:
            return
        page.wait_for_timeout(500)


LIVE = Web(
    text=lambda url: _get(url).text,
    bytes=lambda url: _get(url).content,
    page=_page,
    rendered=_rendered,
)


def with_base(source: str, url: str) -> str:
    """Pin relative addresses to the address the page was finally served from."""
    if re.search(r"<base\s[^>]*href", source, re.I):
        return source
    tag = f'<base href="{escape(url, quote=True)}">'
    head = re.search(r"<head(?:\s[^>]*)?>", source, re.I)
    if head:
        return source[:head.end()] + tag + source[head.end():]
    declaration = re.match(r"\s*<\?xml[^>]*\?>", source)
    at = declaration.end() if declaration else 0
    return source[:at] + tag + source[at:]

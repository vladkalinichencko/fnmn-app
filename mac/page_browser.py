"""Read a page through Google Chrome when a plain HTTP fetch gets nothing to parse.

Some sites refuse scripted HTTP clients or send an empty shell that their own
scripts fill in. Chrome runs as an ordinary visible browser, placed off screen,
and returns the DOM after the page has loaded. One page is open at a time.
"""

from __future__ import annotations

import threading

from playwright.sync_api import Error, sync_playwright

from html_markdown import with_base

_LOCK = threading.Lock()
_SETTLE_MS = 10_000


def rendered_page(url: str) -> str:
    with _LOCK, sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            channel="chrome",
            headless=False,
            args=["--window-position=-2400,-2400", "--window-size=1280,1600"],
        )
        try:
            page = browser.new_page()
            documents = []
            page.on("response", lambda response: documents.append(response)
                    if response.request.is_navigation_request() and response.frame == page.main_frame else None)
            page.goto(url, wait_until="load", timeout=45_000)
            try:
                page.wait_for_load_state("networkidle", timeout=_SETTLE_MS)
            except Error:
                pass
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

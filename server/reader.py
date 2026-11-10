"""The reader browser: one real Chrome per profile, driven over the DevTools protocol.

A plain fetch reads a dynamic page as an empty shell, and a headless Chrome names itself
HeadlessChrome, which sites refuse. So a dynamic page is read in a real Chrome window on the
profile's login: the app hides itself while it works, so to the site it is the owner at the
keyboard. The browser starts on demand for a job and closes after it; the login lives in the
profile on disk, so a closed browser loses nothing.

    with reader.job("x") as tab:
        tab.goto(url)
        tab.settle()
        markup = tab.html()

`job` starts Chrome if it is not running, opens one tab, and closes the browser on exit.
"""

from __future__ import annotations

import json
import random
import subprocess
import threading
import time
import urllib.request
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

import httpx
import websocket

PROFILES = Path(__file__).resolve().parent / "digest" / "profiles"
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
FLAGS = [
    "--remote-debugging-port=0",
    "--disable-blink-features=AutomationControlled",
    "--no-first-run",
    "--no-default-browser-check",
    "--window-position=40,60",
    "--window-size=1280,1600",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-background-timer-throttling",
]
_SETTLE_MS = 10_000
_LOCKS: dict[str, threading.Lock] = {}
_LOCKS_GUARD = threading.Lock()


class ReaderError(Exception):
    """The reader browser could not do what was asked; the reason is for the job's log."""


def profile(network: str) -> Path:
    return PROFILES / network


def available(network: str) -> bool:
    """A Chrome on this profile is running and answers the DevTools protocol."""
    return endpoint(network) is not None


def endpoint(network: str) -> str | None:
    port_file = profile(network) / "DevToolsActivePort"
    try:
        port = int(port_file.read_text(encoding="utf-8").splitlines()[0])
        with urllib.request.urlopen(f"http://localhost:{port}/json/version", timeout=2) as answer:
            if b"Chrome" in answer.read():
                return f"http://localhost:{port}"
    except (OSError, ValueError, IndexError):
        pass
    return None


def _lock(network: str) -> threading.Lock:
    with _LOCKS_GUARD:
        return _LOCKS.setdefault(network, threading.Lock())


class Connection:
    """One websocket to the browser, flat protocol: every call names its session."""

    def __init__(self, http: str):
        version = json.loads(urllib.request.urlopen(f"{http}/json/version", timeout=10).read())
        self.ws = websocket.create_connection(version["webSocketDebuggerUrl"], timeout=60, max_size=256 * 1024 * 1024, suppress_origin=True)
        self.next_id = 0
        self.events: list[dict] = []

    def call(self, method: str, params: dict | None = None, session: str | None = None, timeout: float = 60) -> dict:
        self.next_id += 1
        message_id = self.next_id
        payload = {"id": message_id, "method": method, "params": params or {}}
        if session:
            payload["sessionId"] = session
        deadline = time.monotonic() + timeout
        self.ws.send(json.dumps(payload))
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ReaderError(f"{method} timed out")
            self.ws.settimeout(remaining)
            reply = json.loads(self.ws.recv())
            if reply.get("id") == message_id:
                if "error" in reply:
                    raise ReaderError(f"{method}: {reply['error']}")
                return reply.get("result", {})
            self.events.append(reply)

    def close(self) -> None:
        self.ws.close()


class Tab:
    """A page of the reader browser. The methods keep the names the digest parsers already use."""

    def __init__(self, connection: Connection):
        self.connection = connection
        target = connection.call("Target.createTarget", {"url": "about:blank"})
        self.target_id = target["targetId"]
        session = connection.call("Target.attachToTarget", {"targetId": self.target_id, "flatten": True})
        self.session = session["sessionId"]
        self.call("Page.enable")
        self.call("Network.enable")
        self.call("Runtime.enable")

    def call(self, method: str, params: dict | None = None, timeout: float = 60) -> dict:
        return self.connection.call(method, params, session=self.session, timeout=timeout)

    @property
    def url(self) -> str:
        return self.eval("location.href") or ""

    def goto(self, url: str, timeout: float = 45) -> None:
        self.connection.events.clear()
        try:
            self.call("Page.navigate", {"url": url}, timeout=timeout)
        except ReaderError as error:
            if "net::ERR_ABORTED" not in str(error):
                raise
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if self.eval("document.readyState") in ("interactive", "complete"):
                    return
            except ReaderError:
                pass
            time.sleep(0.2)
        raise ReaderError(f"the page did not load: {url}")

    def document_status(self) -> int | None:
        """The status of the navigation document, when the network saw one."""
        for event in reversed(self.connection.events):
            if event.get("method") == "Network.responseReceived":
                response = event["params"].get("response", {})
                if response.get("type") == "Document":
                    return int(response.get("status") or 0) or None
        return None

    def settle(self) -> None:
        """A page that draws its article from script keeps growing after the load, so read it once its
        text has stood still for three seconds."""
        lengths: list[int] = []
        for _ in range(2 * _SETTLE_MS // 500):
            try:
                lengths.append(int(self.eval("document.body ? document.body.innerText.length : 0") or 0))
            except ReaderError:
                lengths.append(-1)
            if len(lengths) > 6 and len(set(lengths[-7:])) == 1:
                return
            time.sleep(0.5)

    def html(self) -> str:
        return self.eval("document.documentElement.outerHTML") or ""

    def render(self, url: str) -> str:
        """The page's HTML once its script-built text stands still. A bot-challenge interstitial runs its
        own script and reloads; the read waits that out. A page that keeps interjecting raises."""
        self.goto(url)
        self.settle()
        for _ in range(3):
            banner = self.eval("document.body ? document.body.innerText.slice(0, 300) : ''") or ""
            if "JavaScript is not available" not in banner:
                return self.html()
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                time.sleep(2)
                banner = self.eval("document.body ? document.body.innerText.slice(0, 300) : ''") or ""
                if "JavaScript is not available" not in banner:
                    break
            self.settle()
        raise ReaderError(f"the page kept showing a challenge: {url}")

    def eval(self, expression: str) -> object:
        result = self.call("Runtime.evaluate", {"expression": expression, "returnByValue": True})
        if result.get("exceptionDetails"):
            raise ReaderError(f"the page script failed: {result['exceptionDetails'].get('text')}")
        return result.get("result", {}).get("value")

    def wait_for_selector(self, selector: str, timeout: float = 20) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.eval(f"!!document.querySelector({json.dumps(selector)})"):
                return
            time.sleep(0.25)
        raise ReaderError(f"the page never showed {selector}")

    def eval_on_selector_all(self, selector: str, function: str) -> list:
        script = f"[...document.querySelectorAll({json.dumps(selector)})].map({function})"
        return self.eval(script) or []

    def wheel(self, delta_y: int) -> None:
        x, y = random.randint(300, 900), random.randint(300, 1100)
        self.call("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
        self.call("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": x, "y": y, "deltaX": 0, "deltaY": delta_y})

    def wait_for_timeout(self, milliseconds: float) -> None:
        time.sleep(milliseconds / 1000)

    def crawl(self, steps: int, pause: tuple[float, float] = (0.8, 2.2)) -> None:
        """Feeds and conversations keep their further items below the fold; the wheel reaches them in
        human-sized steps."""
        for _ in range(steps):
            self.wheel(random.randint(600, 1400))
            time.sleep(random.uniform(*pause))

    def fetch(self, url: str) -> bytes:
        """One request through the profile's cookies, for media a CDN serves only to the logged-in page."""
        cookies = self.call("Network.getCookies", {"urls": [url]}).get("cookies", [])
        header = "; ".join(f"{cookie['name']}={cookie['value']}" for cookie in cookies)
        headers = {"Cookie": header} if header else {}
        response = httpx.get(url, timeout=30, headers=headers, follow_redirects=True)
        response.raise_for_status()
        return response.content

    def close(self) -> None:
        try:
            self.connection.call("Target.closeTarget", {"targetId": self.target_id})
        except ReaderError:
            pass


class Reader:
    """The running browser of one profile; its window is parked off the screen while it works."""

    def __init__(self, network: str, process: subprocess.Popen | None, connection: Connection):
        self.network = network
        self.process = process
        self.connection = connection

    def tab(self) -> Tab:
        return Tab(self.connection)

    def set_visible(self, visible: bool) -> None:
        """The window shows at the corner of the screen, or parks mostly off its left edge, through the
        DevTools protocol itself: no macOS permissions are asked, and the read-back bounds say where
        the window actually stands."""
        tab = self.tab()
        try:
            info = self.connection.call("Browser.getWindowForTarget", {"targetId": tab.target_id})
            wanted = {"left": 60, "top": 60} if visible else {"left": -2000, "top": 40}
            self.connection.call("Browser.setWindowBounds", {"windowId": info["windowId"], "bounds": wanted})
            left = self.connection.call("Browser.getWindowForTarget", {"targetId": tab.target_id})["bounds"].get("left", 0)
            if not visible and left > -1200:
                self.connection.call("Browser.setWindowBounds", {"windowId": info["windowId"], "bounds": {"left": -2000 - (left + 2000), "top": 40}})
        finally:
            tab.close()

    def hide(self) -> None:
        self.set_visible(False)

    def show(self) -> None:
        self.set_visible(True)

    def close(self) -> None:
        """A browser this job started closes with the job; one it attached to (the login keeps it open)
        keeps running."""
        if self.process is None:
            return
        try:
            self.connection.call("Browser.close", timeout=10)
        except (ReaderError, OSError):
            pass
        try:
            self.process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            self.process.terminate()


def ensure(network: str, visible: bool = False) -> Reader:
    """The running browser of the profile, launching it when it is not there."""
    with _lock(network):
        existing = endpoint(network)
        process = None
        if existing is None:
            folder = profile(network)
            folder.mkdir(parents=True, exist_ok=True)
            for stale in ("DevToolsActivePort", "SingletonLock", "SingletonSocket", "SingletonCookie"):
                (folder / stale).unlink(missing_ok=True)
            process = subprocess.Popen(
                [str(CHROME), f"--user-data-dir={folder}", *FLAGS],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            existing = _wait_for_endpoint(network)
        connection = Connection(existing)
        reader = Reader(network, process, connection)
        if not visible:
            reader.hide()
        return reader


def _wait_for_endpoint(network: str, timeout: float = 30) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = endpoint(network)
        if found:
            return found
        time.sleep(0.3)
    raise ReaderError(f"Chrome did not open its DevTools port for the {network} profile")


@contextmanager
def job(network: str, visible: bool = False) -> Iterator[Tab]:
    """One tab of the profile's browser; a browser the job started closes with it."""
    session = ensure(network, visible=visible)
    tab = session.tab()
    try:
        yield tab
    finally:
        tab.close()
        session.close()

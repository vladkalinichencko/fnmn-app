"""The reader browser: one real Chrome per profile, driven over the DevTools protocol.

A plain fetch reads a dynamic page as an empty shell. A page that needs a browser is read in Chrome's
new headless mode with its automation markers off: there is no window, no Dock icon, nothing to hide,
and `navigator.webdriver` stays false. The browser starts on demand for a job and closes after it; the
login lives in the profile on disk, so a closed browser loses nothing. A login itself runs once in a
headed window, because a network will not log a headless browser in.

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
HEADLESS = [
    "--headless=new",
    "--remote-debugging-port=0",
    "--disable-blink-features=AutomationControlled",
    "--no-first-run",
    "--no-default-browser-check",
]
WINDOWED = [
    "--remote-debugging-port=0",
    "--disable-blink-features=AutomationControlled",
    "--no-first-run",
    "--no-default-browser-check",
    "--hide-crash-restore-bubble",
    "--disable-session-crashed-bubble",
    "--window-position=40,60",
    "--window-size=1280,1600",
]
_SETTLE_MS = 10_000
_LOCKS: dict[str, threading.Lock] = {}
_LOCKS_GUARD = threading.Lock()
_SESSIONS: dict[str, tuple[Reader, int]] = {}


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

    def __init__(self, connection: Connection, background: bool = False):
        self.connection = connection
        target = connection.call("Target.createTarget", {"url": "about:blank", "background": background})
        self.target_id = target["targetId"]
        session = connection.call("Target.attachToTarget", {"targetId": self.target_id, "flatten": True})
        self.session = session["sessionId"]
        self.call("Page.enable")
        self.call("Network.enable")
        self.call("Runtime.enable")
        agent = self.eval("navigator.userAgent") or ""
        if "HeadlessChrome" in agent:
            self.call("Emulation.setUserAgentOverride", {"userAgent": agent.replace("HeadlessChrome", "Chrome")})

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

    def tab(self, background: bool = False) -> Tab:
        return Tab(self.connection, background=background)

    def close(self) -> None:
        """A browser this job started closes with the job; one it attached to keeps running."""
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


def _launch(network: str) -> Reader:
    folder = profile(network)
    folder.mkdir(parents=True, exist_ok=True)
    for stale in ("DevToolsActivePort", "SingletonLock", "SingletonSocket", "SingletonCookie"):
        (folder / stale).unlink(missing_ok=True)
    process = subprocess.Popen(
        [str(CHROME), f"--user-data-dir={folder}", *HEADLESS],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return Reader(network, process, Connection(_wait_for_endpoint(network)))


def ensure(network: str, headed: bool = False) -> Reader:
    """The running browser of the profile, launching it when it is not there. Jobs run headless; a
    login runs headed, in a window the network's check accepts."""
    if headed:
        return _launch_headed(network)
    with _lock(network):
        session = _SESSIONS.get(network)
        if session is None:
            existing = endpoint(network)
            browser = Reader(network, None, Connection(existing)) if existing else _launch(network)
            session = (browser, 0)
        _SESSIONS[network] = (session[0], session[1] + 1)
        return session[0]


def _launch_headed(network: str) -> Reader:
    folder = profile(network)
    folder.mkdir(parents=True, exist_ok=True)
    for stale in ("DevToolsActivePort", "SingletonLock", "SingletonSocket", "SingletonCookie"):
        (folder / stale).unlink(missing_ok=True)
    process = subprocess.Popen(
        [str(CHROME), f"--user-data-dir={folder}", *WINDOWED],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return Reader(network, process, Connection(_wait_for_endpoint(network)))


def _wait_for_endpoint(network: str, timeout: float = 30) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = endpoint(network)
        if found:
            return found
        time.sleep(0.3)
    raise ReaderError(f"Chrome did not open its DevTools port for the {network} profile")


def _release(network: str, session: Reader) -> None:
    with _lock(network):
        current = _SESSIONS.get(network)
        if current is None or current[0] is not session:
            return
        if current[1] == 1:
            session.close()
            del _SESSIONS[network]
        else:
            _SESSIONS[network] = (current[0], current[1] - 1)


@contextmanager
def job(network: str) -> Iterator[Tab]:
    """One tab of the profile's headless browser. Concurrent jobs share one browser; the last job closes
    the browser it started. A session whose browser died is dropped and the job retries once on a fresh
    one, so one crash does not fail every source that follows it."""
    session = ensure(network)
    try:
        tab = session.tab()
    except (OSError, ReaderError):
        _release(network, session)
        session = ensure(network)
        tab = session.tab()
    try:
        yield tab
    finally:
        tab.close()
        _release(network, session)

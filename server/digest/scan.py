"""List who the logged-in profile follows on each network and keep the list in subscriptions.json.

    python -m digest.scan [--network x] [--dry-run]

The scan reconciles: a source the owner wrote by hand keeps its folders, its name and its scope,
a scanned source the profile no longer follows is dropped, and a recommendation feed always stays.
Telegram's channels come from the `telegram` CLI's own session, so private channels without a
public username are the only ones it cannot name.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

from digest.reading import SourceFailure, browser

HERE = Path(__file__).resolve().parent
HOME = {"x": "https://x.com", "instagram": "https://www.instagram.com", "telegram": "https://web.telegram.org"}
RESERVED = {
    "", "home", "explore", "explorepeople", "reels", "stories", "direct", "accounts", "p", "reel",
    "notifications", "messages", "i", "settings", "search", "compose", "login", "logout", "about",
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Add the followed accounts of each network to subscriptions.json")
    parser.add_argument("--network", choices=sorted(HOME), help="scan one network only")
    parser.add_argument("--subscriptions", default=str(HERE / "subscriptions.json"), help="the subscriptions file")
    parser.add_argument("--dry-run", action="store_true", help="print the additions without writing")
    options = parser.parse_args(argv)
    path = Path(options.subscriptions)
    subscriptions = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"folders": [], "sources": []}
    networks = [options.network] if options.network else sorted(HOME)
    additions: list[dict] = []
    scanned: list[str] = []
    for network in networks:
        try:
            if network in TAB_SCANNERS:
                with browser(network) as tab:
                    additions += _SCANNERS[network](tab)
            else:
                additions += _SCANNERS[network]()
            scanned.append(network)
        except SourceFailure as failure:
            print(f"{network}: {failure.reason}")
        except Exception as error:
            print(f"{network}: the scan failed: {error}")
    merged, fresh = merge(subscriptions, additions, scanned)
    for source in fresh:
        name = f" ({source['name']})" if source.get("name") else ""
        print(f"+ {source['id']}{name}")
    if options.dry_run:
        print(f"{len(fresh)} new sources; subscriptions.json untouched")
        return 0
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(fresh)} new sources written to {path}")
    return 0


def merge(subscriptions: dict, additions: list[dict], scanned: list[str]) -> tuple[dict, list[dict]]:
    """The subscriptions reconciled with what the profiles showed: an id already there keeps its entry,
    a scanned source the profile no longer follows is dropped, and a source written by hand always stays."""
    followed = {source["id"] for source in additions}
    sources = [
        source for source in subscriptions.get("sources", [])
        if source.get("network") not in scanned
        or not source.get("scanned")
        or source["id"] in followed
    ]
    known = {source["id"] for source in sources}
    fresh = [source for source in additions if source["id"] not in known]
    return {**subscriptions, "sources": sources + fresh}, fresh


def _x(tab) -> list[dict]:
    """The Following page of the profile's own account: one row per account it follows."""
    tab.goto(f"{HOME['x']}/home")
    tab.settle()
    try:
        tab.wait_for_selector('a[data-testid="AppTabBar_Profile_Link"]', timeout=20)
    except Exception as error:
        raise SourceFailure(f"x.com did not render the profile's navigation: {error}") from error
    href = tab.eval("document.querySelector('a[data-testid=\"AppTabBar_Profile_Link\"]')?.getAttribute('href')") or ""
    me = href.strip("/").split("/")[0]
    if not me:
        raise SourceFailure("x.com did not name the profile's own account")
    tab.goto(f"{HOME['x']}/{me}/following")
    tab.wait_for_selector('[data-testid="UserCell"], [data-testid="cellInnerDiv"]', timeout=20)
    rows: list[dict] = []
    for _ in range(8):
        found = tab.eval(X_CELLS) or []
        rows += [row for row in found if isinstance(row, dict)]
        tab.wheel(1200)
        tab.wait_for_timeout(900)
    return _account_sources("x", rows, me)


def _instagram(tab) -> list[dict]:
    """The Following dialog of the profile's own account. Its name comes from the settings page,
    whose only profile link is the account's own; the home page's nav label is localized."""
    tab.goto(f"{HOME['instagram']}/accounts/edit/")
    tab.settle()
    me = _handle(tab.eval(INSTAGRAM_ME) or "")
    if not me:
        raise SourceFailure("instagram.com did not name the profile's own account")
    tab.goto(f"{HOME['instagram']}/{me}/")
    tab.settle()
    tab.eval(INSTAGRAM_OPEN_FOLLOWING)
    tab.wait_for_selector('[role="dialog"]', timeout=20)
    rows: list[dict] = []
    stable = empty = 0
    for _ in range(150):
        found = [row for row in (tab.eval(INSTAGRAM_FOLLOWING) or []) if isinstance(row, dict)]
        before = len(rows)
        known = {row["href"] for row in rows}
        rows += [row for row in found if row["href"] not in known]
        at_bottom = bool(tab.eval(INSTAGRAM_AT_BOTTOM))
        stable = stable + 1 if len(rows) == before and at_bottom else 0
        empty = empty + 1 if not rows else 0
        if (rows and stable >= 4) or empty >= 15:
            break
        tab.eval(INSTAGRAM_SCROLL)
        tab.wait_for_timeout(800)
    return _account_sources("instagram", rows, me)


def _telegram() -> list[dict]:
    """Every channel the account follows, through the Telegram CLI's own session; a channel
    without a public username has no `t.me` page the digest could read, so it is left out."""
    binary = shutil.which("telegram")
    if binary is None:
        raise SourceFailure("the telegram CLI is not installed")
    completed = subprocess.run(
        [binary, "chats", "--type", "channel", "-n", "500", "--json", "--preview", "0"],
        capture_output=True, text=True, timeout=120,
    )
    if completed.returncode != 0:
        raise SourceFailure(f"telegram chats failed: {completed.stderr.strip()[:200]}")
    chats = json.loads(completed.stdout or "[]")
    sources = []
    for chat in chats:
        if chat.get("type") != "channel":
            continue
        channel = (chat.get("username") or "").strip().lstrip("@")
        if not channel or channel.lower() in RESERVED:
            continue
        source = {"id": f"telegram/{channel}", "network": "telegram", "channel": channel, "folders": [], "scanned": True}
        title = (chat.get("title") or "").strip()
        if title:
            source["name"] = title
        sources.append(source)
    return sources


def _account_sources(network: str, rows: list[dict], me: str) -> list[dict]:
    """Profile rows ({handle|href, name}) as subscription sources, deduplicated, without reserved pages."""
    sources = []
    seen = set()
    for row in rows:
        handle = _handle(row.get("handle") or row.get("href") or "")
        if not handle or handle == me.lower() or handle in seen or handle in RESERVED:
            continue
        seen.add(handle)
        source = {"id": f"{network}/{handle}", "network": network, "handle": handle, "folders": [], "scanned": True}
        name = (row.get("name") or "").strip()
        if name:
            source["name"] = name
        sources.append(source)
    return sources


def _handle(value: str) -> str:
    parts = [part for part in value.strip().strip("/").split("/") if part]
    return parts[0].lower() if parts else ""


X_CELLS = """[...document.querySelectorAll('[data-testid="UserCell"], [data-testid="cellInnerDiv"]')].map(cell => {
  const link = cell.querySelector('a[href^="/"]');
  const name = cell.querySelector('[data-testid="User-Name"]');
  return {href: link ? link.getAttribute('href') : '', name: name ? name.innerText.split('\\n')[0].trim() : ''};
}).filter(row => row.href)"""

INSTAGRAM_ME = """[...document.querySelectorAll('a[href]')]
  .map(a => a.getAttribute('href') || '')
  .map(href => href.replace(/\\/$/, ''))
  .find(href => /^\\/[A-Za-z0-9._]+$/.test(href)
    && !['/reels','/explore','/popular','/accounts','/direct','/p','/reel','/tv'].includes(href)) || ''"""

INSTAGRAM_OPEN_FOLLOWING = """[...document.querySelectorAll('a[role="link"]')]
  .find(a => /following/i.test(a.innerText || '') && (a.innerText || '').length < 40)?.click()"""

INSTAGRAM_SCROLL = """(() => {
  const dialog = document.querySelector('[role="dialog"]');
  const scroller = dialog && [...dialog.querySelectorAll('div')]
    .filter(d => d.scrollHeight > d.clientHeight + 50)
    .sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
  if (scroller) scroller.scrollTop += scroller.clientHeight * 2;
})()"""

INSTAGRAM_AT_BOTTOM = """(() => {
  const dialog = document.querySelector('[role="dialog"]');
  const scroller = dialog && [...dialog.querySelectorAll('div')]
    .filter(d => d.scrollHeight > d.clientHeight + 50)
    .sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
  return !!scroller && scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 20;
})()"""

INSTAGRAM_FOLLOWING = """[...document.querySelectorAll('[role="dialog"] a[href^="/"]')].map(a => ({
  href: a.getAttribute('href'),
  name: (a.innerText || '').split('\\n')[0].trim(),
})).filter(row => row.href.split('/').filter(Boolean).length === 1)"""

TAB_SCANNERS = {"x", "instagram"}
_SCANNERS = {"x": _x, "instagram": _instagram, "telegram": _telegram}


if __name__ == "__main__":
    raise SystemExit(main())

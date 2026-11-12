"""List who the logged-in profile follows on each network and keep the list in subscriptions.json.

    python -m digest.scan [--network x] [--dry-run]

The scan only adds: a source the owner wrote by hand keeps its folders, its name and its scope,
and a source the profile no longer shows stays, because a stale entry costs one failed read while
a removed one loses its topics. Telegram's web client exposes public channels only as the `t.me`
links its chats contain, so its scan finds what the conversations themselves link to.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from digest.reading import SourceFailure, browser

HERE = Path(__file__).resolve().parent
HOME = {"x": "https://x.com", "instagram": "https://www.instagram.com", "telegram": "https://web.telegram.org"}
RESERVED = {
    "", "home", "explore", "explorepeople", "reels", "stories", "direct", "accounts", "p", "reel",
    "notifications", "messages", "i", "settings", "search", "compose", "login", "logout", "about",
}
T_ME = re.compile(r"t\.me/(?:s/)?([A-Za-z0-9_]+)")


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
    for network in networks:
        try:
            with browser(network) as tab:
                additions += _SCANNERS[network](tab)
        except SourceFailure as failure:
            print(f"{network}: {failure.reason}")
        except Exception as error:
            print(f"{network}: the scan failed: {error}")
    merged, fresh = merge(subscriptions, additions)
    for source in fresh:
        name = f" ({source['name']})" if source.get("name") else ""
        print(f"+ {source['id']}{name}")
    if options.dry_run:
        print(f"{len(fresh)} new sources; subscriptions.json untouched")
        return 0
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(fresh)} new sources written to {path}")
    return 0


def merge(subscriptions: dict, additions: list[dict]) -> tuple[dict, list[dict]]:
    """The subscriptions with the discovered sources appended; an id already there keeps its entry."""
    sources = list(subscriptions.get("sources", []))
    known = {source["id"] for source in sources}
    fresh = [source for source in additions if source["id"] not in known]
    return {**subscriptions, "sources": sources + fresh}, fresh


def _x(tab) -> list[dict]:
    """The Following page of the profile's own account: one row per account it follows."""
    tab.goto(f"{HOME['x']}/home")
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
    """The Following dialog of the profile's own account."""
    tab.goto(f"{HOME['instagram']}/")
    href = tab.eval(INSTAGRAM_ME) or ""
    me = href.strip("/").split("/")[0]
    if not me:
        raise SourceFailure("instagram.com did not name the profile's own account")
    tab.goto(f"{HOME['instagram']}/{me}/")
    tab.eval("document.querySelector('a[href$=\"/following/\"]')?.click()")
    tab.wait_for_selector('[role="dialog"]', timeout=20)
    rows = tab.eval(INSTAGRAM_FOLLOWING) or []
    return _account_sources("instagram", [row for row in rows if isinstance(row, dict)], me)


def _telegram(tab) -> list[dict]:
    """The `t.me` links the logged-in chats contain; a channel without a public name cannot be read."""
    tab.goto(f"{HOME['telegram']}/")
    tab.wait_for_selector(".chatlist, .ListItem, .chatlist-chat", timeout=30)
    hrefs = tab.eval("[...document.querySelectorAll('a[href*=\"t.me/\"]')].map(a => a.href)") or []
    channels = sorted({match.group(1) for href in hrefs if (match := T_ME.search(href or ""))})
    return [
        {"id": f"telegram/{channel}", "network": "telegram", "channel": channel, "folders": []}
        for channel in channels if channel.lower() not in RESERVED
    ]


def _account_sources(network: str, rows: list[dict], me: str) -> list[dict]:
    """Profile rows ({handle|href, name}) as subscription sources, deduplicated, without reserved pages."""
    sources = []
    seen = set()
    for row in rows:
        handle = _handle(row.get("handle") or row.get("href") or "")
        if not handle or handle == me.lower() or handle in seen or handle in RESERVED:
            continue
        seen.add(handle)
        source = {"id": f"{network}/{handle}", "network": network, "handle": handle, "folders": []}
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

INSTAGRAM_ME = """[...document.querySelectorAll('a[href^="/"]')]
  .find(a => a.innerText.trim() === 'Profile')?.getAttribute('href') || ''"""

INSTAGRAM_FOLLOWING = """[...document.querySelectorAll('[role="dialog"] a[href^="/"]')].map(a => ({
  href: a.getAttribute('href'),
  name: (a.innerText || '').split('\\n')[0].trim(),
})).filter(row => row.href.split('/').filter(Boolean).length === 1)"""

_SCANNERS = {"x": _x, "instagram": _instagram, "telegram": _telegram}


if __name__ == "__main__":
    raise SystemExit(main())

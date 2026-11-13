"""One pass over the subscription sources: every source reads the posts it has not been read for, the store
keeps them, and the digest builder picks them up at its next scheduled time. Run by launchd every two hours;
a run that finds nothing new writes nothing.

    python -m digest.monitor [--only x/karpathy] [--verbose]
"""

from __future__ import annotations

import argparse
import json
import traceback
from datetime import datetime, timezone
from pathlib import Path

from digest import instagram, settings as digest_settings, telegram, x
from digest.reading import SourceFailure, SourceResult, browser, needs_browser
from digest.store import Store, iso
from web import LIVE
import reader

HERE = Path(__file__).resolve().parent
SOURCES = {"x": x, "telegram": telegram, "instagram": instagram}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read the subscription sources once")
    parser.add_argument("--only", help="one source id from subscriptions.json")
    parser.add_argument("--verbose", action="store_true")
    options = parser.parse_args(argv)
    prefs = digest_settings.load()
    if not prefs["enabled"]:
        print("the digest is off in its settings")
        return 0
    subscriptions = json.loads((HERE / "subscriptions.json").read_text(encoding="utf-8"))
    sources = list(subscriptions["sources"])
    for network in digest_settings.RECOMMENDATION_NETWORKS:
        if digest_settings.recommendations(prefs, network):
            sources.append({
                "id": f"{network}/recommendations",
                "network": network,
                "name": "Recommendations",
                "scope": "recommendations",
                "folders": [],
            })
    store = Store()
    statuses = {status["id"]: status for status in store.source_statuses()}
    for source in sources:
        if options.only and source["id"] != options.only:
            continue
        status = _run(source, subscriptions["folders"], store, options.verbose)
        statuses[source["id"]] = {
            "id": source["id"],
            "network": source["network"],
            "name": source.get("name") or status.get("name") or source["id"],
            "folders": source.get("folders", []),
            **status,
        }
    ordered = [statuses[source["id"]] for source in sources if source["id"] in statuses]
    store.save_source_statuses(ordered)
    print(f"{iso(datetime.now(timezone.utc))}: {len(ordered)} sources, statuses written")
    return 0


def _run(source: dict, folders: list[str], store: Store, verbose: bool) -> dict:
    module = SOURCES[source["network"]]

    def report(stage: str) -> None:
        if verbose:
            print(f"{source['id']}: {stage}")

    try:
        result = _collect(source, module, store, report)
    except SourceFailure as failure:
        if source["network"] != "x" or not _warm_x(source, verbose):
            print(f"{source['id']}: failed: {failure.reason}")
            return {"status": "failed", "detail": failure.reason}
        try:
            result = _collect(source, module, store, report)
        except SourceFailure as retry:
            print(f"{source['id']}: failed: {retry.reason}")
            return {"status": "failed", "detail": retry.reason}
        except Exception as error:
            traceback.print_exc()
            return {"status": "failed", "detail": str(error)}
    except Exception as error:
        traceback.print_exc()
        return {"status": "failed", "detail": str(error)}
    added = store.append(result.posts)
    print(f"{source['id']}: {added} new of {len(result.posts)} read")
    if result.note:
        return {"status": "stale", "detail": result.note, "name": result.name}
    return {"status": "ok", "name": result.name}


def _collect(source: dict, module, store: Store, report) -> SourceResult:
    if needs_browser(source["network"]):
        with browser(source["network"]) as page:
            return module.collect(source, LIVE, store, source.get("folders", []), report, page=page)
    return module.collect(source, LIVE, store, source.get("folders", []), report)


def _warm_x(source: dict, verbose: bool) -> bool:
    """One headed visit to x.com: Cloudflare issues the cf_clearance the headless profile then reuses."""
    print(f"{source['id']}: x refused headless; warming the profile")
    try:
        session = reader.ensure("x", headed=True)
    except Exception as error:
        if verbose:
            print(f"{source['id']}: the warmup browser did not open: {error}")
        return False
    warmed = False
    try:
        tab = session.tab(background=True)
        try:
            tab.goto("https://x.com", timeout=45)
            tab.settle()
            tab.wait_for_timeout(2000)
            warmed = "x.com" in tab.url
        finally:
            tab.close()
    except Exception:
        pass
    finally:
        session.close()
    return warmed


if __name__ == "__main__":
    raise SystemExit(main())

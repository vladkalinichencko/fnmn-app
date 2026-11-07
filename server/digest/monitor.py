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

from digest import instagram, telegram, x
from digest.sources import SourceFailure, browser
from digest.store import Store, iso
from web import LIVE

HERE = Path(__file__).resolve().parent
SOURCES = {"x": x, "telegram": telegram, "instagram": instagram}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read the subscription sources once")
    parser.add_argument("--only", help="one source id from subscriptions.json")
    parser.add_argument("--verbose", action="store_true")
    options = parser.parse_args(argv)
    subscriptions = json.loads((HERE / "subscriptions.json").read_text(encoding="utf-8"))
    store = Store()
    statuses = {status["id"]: status for status in store.source_statuses()}
    for source in subscriptions["sources"]:
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
    ordered = [statuses[source["id"]] for source in subscriptions["sources"] if source["id"] in statuses]
    store.save_source_statuses(ordered)
    print(f"{iso(datetime.now(timezone.utc))}: {len(ordered)} sources, statuses written")
    return 0


def _run(source: dict, folders: list[str], store: Store, verbose: bool) -> dict:
    module = SOURCES[source["network"]]

    def report(stage: str) -> None:
        if verbose:
            print(f"{source['id']}: {stage}")

    try:
        if source["network"] in ("x", "instagram"):
            with browser(source["network"]) as page:
                result = module.collect(source, LIVE, store, source.get("folders", []), report, page=page)
        else:
            result = module.collect(source, LIVE, store, source.get("folders", []), report)
    except SourceFailure as failure:
        print(f"{source['id']}: failed: {failure.reason}")
        return {"status": "failed", "detail": failure.reason}
    except Exception as error:
        traceback.print_exc()
        return {"status": "failed", "detail": str(error)}
    added = store.append(result.posts)
    print(f"{source['id']}: {added} new of {len(result.posts)} read")
    if result.note:
        return {"status": "stale", "detail": result.note, "name": result.name}
    return {"status": "ok", "name": result.name}


if __name__ == "__main__":
    raise SystemExit(main())

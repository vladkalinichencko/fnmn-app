"""Re-OCR only footnotes whose embedded PDF text contains broken glyphs."""

import json
import re

import ocr_jobs
from grounding import strip as strip_grounding

FOOTNOTE = re.compile(r"\\\(\s*\^\{(\d+)\}\s*\\\)")


def markdown(text):
    return strip_grounding(text)


def select_footnote(text, number):
    markers = list(FOOTNOTE.finditer(text))
    for index, marker in enumerate(markers):
        if marker[1] == str(number):
            end = markers[index + 1].start() if index + 1 < len(markers) else len(text)
            return text[marker.end():end].strip()
    return text


def main() -> None:
    options = ocr_jobs.parse(__doc__)
    candidates = json.loads(options.candidates.read_text())
    jobs = [(page["page"], issue) for page in candidates for issue in page["issues"]
            if issue["type"] == "footnote_needs_ocr"]
    raw = options.output.parent / "footnote-ocr"
    raw.mkdir(parents=True, exist_ok=True)
    overrides = json.loads(options.output.read_text()) if options.output.exists() else {}

    def select(page, issue, text):
        value = select_footnote(markdown(text), issue["number"])
        overrides[f"{page}:{issue['number']}"] = value
        return value

    def metrics(issue, result, seconds, value):
        return {
            "number": issue["number"],
            "generation_tokens": result.generation_tokens,
            "finish_reason": result.finish_reason,
            "wall_seconds": seconds,
        }

    if options.rebuild_only:
        for page, issue in jobs:
            select(page, issue, (raw / f"{page}-{issue['number']}.md").read_text())
        ocr_jobs.save(options.output, overrides)
        return

    ocr_jobs.run(
        jobs,
        candidates=options.candidates,
        output=options.output,
        raw=raw,
        overrides=overrides,
        model_name=options.model,
        label="Footnote OCR",
        unit="footnote",
        key=lambda issue: issue["number"],
        select=select,
        metrics=metrics,
    )


if __name__ == "__main__":
    main()

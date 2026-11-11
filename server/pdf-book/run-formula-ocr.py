"""Re-OCR formula crops whose braces or delimiters do not determine one repair."""

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ocr_jobs
from math_issues import formula_jobs, select_formula


def main() -> None:
    options = ocr_jobs.parse(__doc__)
    candidates = json.loads(options.candidates.read_text())
    jobs = formula_jobs(candidates)
    raw = options.output.parent / "formula-ocr"
    raw.mkdir(parents=True, exist_ok=True)
    overrides = json.loads(options.output.read_text()) if options.output.exists() else {}

    def select(page, issue, text):
        key = f"{page}:{issue['equation']}"
        formula = select_formula(text)
        if formula:
            overrides[key] = formula
        else:
            overrides.pop(key, None)
        return formula

    def metrics(issue, result, seconds, value):
        return {
            "equation": issue["equation"],
            "accepted": value is not None,
            "generation_tokens": result.generation_tokens,
            "finish_reason": result.finish_reason,
            "wall_seconds": seconds,
        }

    if options.rebuild_only:
        for page, issue in jobs:
            select(page, issue, (raw / f"{page}-{issue['equation']}.md").read_text())
        ocr_jobs.save(options.output, overrides)
        return

    ocr_jobs.run(
        jobs,
        candidates=options.candidates,
        output=options.output,
        raw=raw,
        overrides=overrides,
        model_name=options.model,
        label="Formula OCR",
        unit="formula",
        key=lambda issue: issue["equation"],
        select=select,
        metrics=metrics,
    )


if __name__ == "__main__":
    main()

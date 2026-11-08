"""The one re-OCR pass: load the model once, run every job, keep the raw answer and its metrics."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Callable

from tqdm import tqdm

PROMPT = "<|grounding|>Convert the document to markdown."
MODEL = "mlx-community/DeepSeek-OCR-2-bf16"


def parse(description: str) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("candidates", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--rebuild-only", action="store_true")
    return parser.parse_args()


def save(output: Path, overrides: dict) -> None:
    output.write_text(json.dumps(overrides, ensure_ascii=False, indent=2) + "\n")


def run(
    jobs: list[tuple[int, dict]],
    *,
    candidates: Path,
    output: Path,
    raw: Path,
    overrides: dict,
    model_name: str,
    label: str,
    unit: str,
    key: Callable[[dict], object],
    select: Callable[[int, dict, str], object],
    metrics: Callable[[dict, object, float, object], dict],
) -> None:
    """`key` names a job in `overrides`; `select` writes the chosen answer there and returns it; `metrics`
    describes one call."""
    if not jobs:
        save(output, overrides)
        return
    from mlx_vlm import generate, load
    from mlx_vlm.prompt_utils import apply_chat_template

    model, processor = load(model_name, trust_remote_code=False)
    prompt = apply_chat_template(processor, model.config, PROMPT, num_images=1)
    for page, issue in tqdm(jobs, desc=label, unit=unit):
        name = key(issue)
        if f"{page}:{name}" in overrides:
            continue
        started = time.monotonic()
        image = candidates.parent / issue["image"]
        result = generate(model, processor, prompt=prompt, image=str(image), max_tokens=3072, temperature=0.0)
        value = select(page, issue, result.text)
        (raw / f"{page}-{name}.md").write_text(result.text)
        (raw / f"{page}-{name}.json").write_text(json.dumps({
            "page": page, **metrics(issue, result, time.monotonic() - started, value),
        }, indent=2) + "\n")
        save(output, overrides)

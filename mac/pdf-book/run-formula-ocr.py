"""Re-OCR formula crops whose braces or delimiters do not determine one repair."""

import argparse
import json
from pathlib import Path
import sys
import time

from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent))
from math_issues import formula_jobs, select_formula  # noqa: E402


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidates', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--model', default='mlx-community/DeepSeek-OCR-2-bf16')
parser.add_argument('--rebuild-only', action='store_true')
options = parser.parse_args()

candidates = json.loads(options.candidates.read_text())
jobs = formula_jobs(candidates)
raw = options.output.parent / 'formula-ocr'
raw.mkdir(parents=True, exist_ok=True)
overrides = json.loads(options.output.read_text()) if options.output.exists() else {}


def store(page, issue, text):
    key = f'{page}:{issue["equation"]}'
    formula = select_formula(text)
    if formula:
        overrides[key] = formula
    else:
        overrides.pop(key, None)
    return formula


if options.rebuild_only:
    for page, issue in jobs:
        store(page, issue, (raw / f'{page}-{issue["equation"]}.md').read_text())
    options.output.write_text(json.dumps(overrides, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit

from mlx_vlm import generate, load  # noqa: E402
from mlx_vlm.prompt_utils import apply_chat_template  # noqa: E402

model, processor = load(options.model, trust_remote_code=False)
prompt = apply_chat_template(
    processor, model.config, '<|grounding|>Convert the document to markdown.', num_images=1)

for page, issue in tqdm(jobs, desc='Formula OCR', unit='formula'):
    key = f'{page}:{issue["equation"]}'
    if key in overrides:
        continue
    started = time.monotonic()
    image = options.candidates.parent / issue['image']
    result = generate(model, processor, prompt=prompt, image=str(image),
                      max_tokens=3072, temperature=0.0)
    formula = store(page, issue, result.text)
    (raw / f'{page}-{issue["equation"]}.md').write_text(result.text)
    (raw / f'{page}-{issue["equation"]}.json').write_text(json.dumps({
        'page': page, 'equation': issue['equation'], 'accepted': formula is not None,
        'generation_tokens': result.generation_tokens, 'finish_reason': result.finish_reason,
        'wall_seconds': time.monotonic() - started,
    }, indent=2) + '\n')
    options.output.write_text(json.dumps(overrides, ensure_ascii=False, indent=2) + '\n')

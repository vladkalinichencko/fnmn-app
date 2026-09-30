"""Re-OCR only footnotes whose embedded PDF text contains broken glyphs."""

import argparse
import json
from pathlib import Path
import re
import time

from tqdm import tqdm


GROUNDING = re.compile(r'<\|ref\|>.*?<\|/ref\|><\|det\|>.*?<\|/det\|>\s*')
FOOTNOTE = re.compile(r'\\\(\s*\^\{(\d+)\}\s*\\\)')


def markdown(text):
    matches = list(GROUNDING.finditer(text))
    if not matches:
        return text.strip()
    return '\n\n'.join(text[match.end():matches[i + 1].start() if i + 1 < len(matches) else len(text)].strip()
                       for i, match in enumerate(matches)).strip()


def select_footnote(text, number):
    markers = list(FOOTNOTE.finditer(text))
    for index, marker in enumerate(markers):
        if marker[1] == str(number):
            end = markers[index + 1].start() if index + 1 < len(markers) else len(text)
            return text[marker.end():end].strip()
    return text


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidates', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--model', default='mlx-community/DeepSeek-OCR-2-bf16')
parser.add_argument('--rebuild-only', action='store_true')
options = parser.parse_args()

candidates = json.loads(options.candidates.read_text())
jobs = [(page['page'], issue) for page in candidates for issue in page['issues']
        if issue['type'] == 'footnote_needs_ocr']
raw = options.output.parent / 'footnote-ocr'
raw.mkdir(parents=True, exist_ok=True)
overrides = json.loads(options.output.read_text()) if options.output.exists() else {}

if options.rebuild_only:
    for page, issue in jobs:
        source = raw / f'{page}-{issue["number"]}.md'
        overrides[f'{page}:{issue["number"]}'] = select_footnote(markdown(source.read_text()), issue['number'])
    options.output.write_text(json.dumps(overrides, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit

from mlx_vlm import generate, load  # noqa: E402
from mlx_vlm.prompt_utils import apply_chat_template  # noqa: E402

model, processor = load(options.model, trust_remote_code=False)
prompt = apply_chat_template(
    processor, model.config, '<|grounding|>Convert the document to markdown.', num_images=1)

for page, issue in tqdm(jobs, desc='Footnote OCR', unit='footnote'):
    key = f'{page}:{issue["number"]}'
    if key in overrides:
        continue
    started = time.monotonic()
    image = options.candidates.parent / issue['image']
    result = generate(model, processor, prompt=prompt, image=str(image),
                      max_tokens=3072, temperature=0.0)
    text = select_footnote(markdown(result.text), issue['number'])
    overrides[key] = text
    (raw / f'{page}-{issue["number"]}.md').write_text(result.text)
    (raw / f'{page}-{issue["number"]}.json').write_text(json.dumps({
        'page': page, 'number': issue['number'], 'generation_tokens': result.generation_tokens,
        'finish_reason': result.finish_reason, 'wall_seconds': time.monotonic() - started,
    }, indent=2) + '\n')
    options.output.write_text(json.dumps(overrides, ensure_ascii=False, indent=2) + '\n')

"""OCR page images or a complete PDF with DeepSeek-OCR-2 on MLX."""

import argparse
import json
import time
from pathlib import Path
from tempfile import TemporaryDirectory

import pymupdf
from tqdm import tqdm

args = argparse.ArgumentParser(description=__doc__)
args.add_argument('pdf', type=Path)
args.add_argument('output', type=Path)
args.add_argument('--model', default='mlx-community/DeepSeek-OCR-2-bf16')
args.add_argument('--pages', nargs='+', type=int)
args.add_argument('--no-repeat-ngram', type=int, default=0)
args.add_argument('--retry-ngram', type=int, default=20)
options = args.parse_args()
output = options.output
output.mkdir(parents=True, exist_ok=True)
from mlx_vlm import generate, load  # noqa: E402
from mlx_vlm.prompt_utils import apply_chat_template  # noqa: E402

started = time.monotonic()
model, processor = load(options.model)
print(f'Model loaded in {time.monotonic() - started:.2f}s', flush=True)
prompt = apply_chat_template(
    processor, model.config,
    '<|grounding|>Convert the document to markdown.', num_images=1,
)
document = pymupdf.open(options.pdf)
pages = options.pages or range(1, len(document) + 1)
invalid_pages = [page for page in pages if page < 1 or page > len(document)]
if invalid_pages:
    args.error(f'pages outside the PDF: {invalid_pages}')

def ngram_blocker(size):
    def block(tokens, logits):
        history = tokens.tolist()
        if len(history) >= size:
            prefix = history[-(size - 1):]
            banned = {history[i + size - 1] for i in range(len(history) - size + 1)
                      if history[i:i + size - 1] == prefix}
            if banned:
                logits[..., list(banned)] = -float('inf')
        return logits
    return block


def repetitive(text):
    tokens = text.split()
    for size in range(1, min(12, len(tokens) // 8) + 1):
        for start in range(len(tokens) - size * 8 + 1):
            phrase = tokens[start:start + size]
            if all(tokens[start + repeat * size:start + (repeat + 1) * size] == phrase
                   for repeat in range(1, 8)):
                return True
    return False


def run(image, ngram):
    return generate(
        model, processor, prompt=prompt, image=str(image),
        max_tokens=6144, temperature=0.0,
        logits_processors=[ngram_blocker(ngram)] if ngram else None,
    )


def metrics(result, page, seconds, ngram):
    values = {key: getattr(result, key) for key in [
        'prompt_tokens', 'generation_tokens', 'generation_tps', 'peak_memory', 'finish_reason',
    ]}
    values.update(page=page, wall_seconds=seconds, no_repeat_ngram=ngram)
    return values

temporary = TemporaryDirectory()
progress = tqdm(pages, desc='DeepSeek-OCR-2', unit='page')
for page in progress:
    started = time.monotonic()
    image = Path(temporary.name) / 'page.png'
    document[page - 1].get_pixmap(dpi=140).save(image)
    result = run(image, options.no_repeat_ngram)
    first_seconds = time.monotonic() - started
    retried = not options.no_repeat_ngram and (result.finish_reason == 'length' or repetitive(result.text))
    if retried:
        (output / f'page-{page}.first.md').write_text(result.text, encoding='utf-8')
        (output / f'page-{page}.first.json').write_text(
            json.dumps(metrics(result, page, first_seconds, 0), indent=2) + '\n')
        result = run(image, options.retry_ngram)
    (output / f'page-{page}.md').write_text(result.text, encoding='utf-8')
    page_metrics = metrics(result, page, time.monotonic() - started,
                           options.retry_ngram if retried else options.no_repeat_ngram)
    page_metrics['retried'] = retried
    (output / f'page-{page}.json').write_text(json.dumps(page_metrics, indent=2) + '\n')
    progress.set_postfix(tokens=result.generation_tokens, seconds=f'{page_metrics["wall_seconds"]:.1f}',
                         finish=result.finish_reason, retried=retried)
temporary.cleanup()
document.close()

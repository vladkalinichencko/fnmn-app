# PDF book pipeline

These scripts turn any born-digital PDF into a checked FNMN book package:

```text
PDF -> grounded page OCR -> deterministic assembly -> typed candidates -> targeted footnote OCR -> checked Markdown -> app package
```

Install the pinned OCR environment:

```bash
python3 -m venv .venv-ocr
.venv-ocr/bin/pip install -r mac/pdf-book/requirements-ocr.txt
```

Run the complete pipeline from the repository root:

```bash
.venv-ocr/bin/python mac/pdf-book/run-ocr2.py \
  /path/to/book.pdf /path/to/work/ocr

.venv-ocr/bin/python mac/pdf-book/assemble-book.py \
  /path/to/book.pdf /path/to/work/ocr /path/to/work/book.md

.venv-ocr/bin/python mac/pdf-book/run-footnote-ocr.py \
  /path/to/work/book.candidates.json /path/to/work/footnote-overrides.json

.venv-ocr/bin/python mac/pdf-book/assemble-book.py \
  /path/to/book.pdf /path/to/work/ocr /path/to/work/book.md \
  --footnote-overrides /path/to/work/footnote-overrides.json

python3 mac/pdf-book/export-app-book.py \
  /path/to/work/book.md /path/to/book-config.json /path/to/output-book
```

`run-ocr2.py` processes every page with DeepSeek-OCR-2 and retries truncated or repetitive output. `assemble-book.py` combines grounded OCR with PDF text, geometry, bookmarks, equations, figures, and footnotes. It writes `book.audit.json`, `book.candidates.json`, `book.validation.json`, and `assets/` beside the Markdown. Candidate records have explicit types such as `footnote_needs_ocr`, `footnote_reference_missing`, `bare_latex`, `unbalanced_math_delimiter`, `unbalanced_environment`, and `repetition`.

`run-footnote-ocr.py` automatically reprocesses only `footnote_needs_ocr` crops. Other candidate types remain visible for review; the pipeline does not ask a model to guess arbitrary corrections. Re-run the assembler after changing overrides or replacement pages.

`export-app-book.py` makes the self-contained directory imported by FNMN: `content.md`, `metadata.json`, `assets/`, and `validation.json`. Its book config contains presentation decisions that cannot be inferred safely: metadata, `content_start`, and sections to omit. [`principles-of-deep-learning-theory.json`](principles-of-deep-learning-theory.json) is an example config, and [`fixtures/books/principles-of-deep-learning-theory/`](../../fixtures/books/principles-of-deep-learning-theory/) is an example output package.

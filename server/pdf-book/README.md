# PDF book pipeline

These scripts turn any born-digital PDF into a checked FNMN book package:

```text
PDF text + grounded page OCR -> assembly -> unambiguous cleanup -> formula and footnote crops back to the model -> app package
```

Install the pinned OCR environment:

```bash
python3 -m venv .venv-ocr
.venv-ocr/bin/pip install -r server/pdf-book/requirements-ocr.txt
```

Run the complete pipeline from the repository root:

```bash
.venv-ocr/bin/python server/pdf-book/run-ocr2.py \
  /path/to/book.pdf /path/to/work/ocr

.venv-ocr/bin/python server/pdf-book/assemble-book.py \
  /path/to/book.pdf /path/to/work/ocr /path/to/work/book.md

.venv-ocr/bin/python server/pdf-book/run-footnote-ocr.py \
  /path/to/work/book.candidates.json /path/to/work/footnote-overrides.json

.venv-ocr/bin/python server/pdf-book/run-formula-ocr.py \
  /path/to/work/book.candidates.json /path/to/work/formula-overrides.json

.venv-ocr/bin/python server/pdf-book/assemble-book.py \
  /path/to/book.pdf /path/to/work/ocr /path/to/work/book.md \
  --footnote-overrides /path/to/work/footnote-overrides.json \
  --formula-overrides /path/to/work/formula-overrides.json

python3 server/pdf-book/export-app-book.py \
  /path/to/work/book.md /path/to/book-config.json /path/to/output-book
```

`run-ocr2.py` sends every full page to DeepSeek-OCR-2 with `Convert the document to markdown` and retries truncated or repetitive output. `assemble-book.py` reads the PDF text layer and combines it with that OCR, geometry, bookmarks, equations, figures, and footnotes. It rewrites only math spellings that have one legal result, such as `\[...\]` to `$$` and `align*` to `aligned`. A brace or `\left`/`\right` repair that has more than one legal result stays an issue and keeps a crop of that equation. The same check later stops `export-app-book.py` from publishing a package that still contains one.

Assembly writes `book.audit.json`, `book.candidates.json`, `book.validation.json`, and `assets/` beside the Markdown. Candidate types include `footnote_needs_ocr`, `footnote_reference_missing`, `bare_latex`, `unbalanced_math_delimiter`, `unbalanced_environment`, `unbalanced_group`, `unbalanced_left_right`, and `repetition`.

`run-footnote-ocr.py` sends each `footnote_needs_ocr` crop back to the same model and prompt. `run-formula-ocr.py` does that for equation crops whose braces or `\left`/`\right` do not balance. A formula transcription is kept only when it contains one math region and that region balances; otherwise the original equation stays and the issue remains. Re-run the assembler with both override files.

`export-app-book.py` makes a self-contained directory: `content.md`, `metadata.json`, `assets/`, and `validation.json`. [`collect/publish_books.py`](../collect/publish_books.py) turns it into one delivery in the FNMN folder, the same archive an article gets, so the app reads a book like any other material. Its book config contains presentation decisions that cannot be inferred safely: metadata, `content_start`, and sections to omit. [`principles-of-deep-learning-theory.json`](principles-of-deep-learning-theory.json) is an example config, and [`fixtures/books/principles-of-deep-learning-theory/`](../../fixtures/books/principles-of-deep-learning-theory/) is an example output package.

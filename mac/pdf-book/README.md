# PDF book package

`export-app-book.py` turns verified archival Markdown into the directory that FNMN will import for a PDF book. The directory is self-contained:

- `content.md` is Markdown from the selected first heading through the retained final section. It has no printed contents, index, PDF-page comments, heading numbers, or page-boundary runs of blank lines.
- `metadata.json` has `schema_version: 1`, `title`, optional `subtitle`, `authors`, optional `contributors`, `language`, `source_name`, `content_file`, `assets_directory`, and the ordered `toc`. Each TOC entry has a one-based `ordinal`, Markdown `level`, and displayed `title`.
- `assets/` contains every image named by `content.md`. Markdown resolves each image relative to this directory.
- `validation.json` records the heading and image counts plus `errors`. Import accepts a package only when `errors` is empty.

The included [`principles-of-deep-learning-theory.json`](principles-of-deep-learning-theory.json) defines the presentation boundary for the sample book. `content_start` and `drop_sections` are per-book decisions. Do not infer them from a publisher's front matter.

To make a package from an already checked archival Markdown file, run this from the repository root:

```bash
python3 mac/pdf-book/export-app-book.py \
  /path/to/book.md \
  mac/pdf-book/principles-of-deep-learning-theory.json \
  /path/to/output-book
```

The source Markdown must have its referenced figure files beside it at the relative paths used in the Markdown. The exporter stops when headings remain numbered, an image is missing, footnote references do not match definitions, or page markers and excess blank lines survive.

`fixtures/books/principles-of-deep-learning-theory/` is the checked package from the completed OCR build. It is a reader fixture and contract sample, not a replacement for the archival OCR run. The full OCR and assembly trail, including model inputs, per-page evidence, candidates, and footnote overrides, remains in the Research Tree artifact that produced this package.

The iPhone/iPad app currently imports the older JSON `ImportPackage` only. The next PDF-reader implementation must copy this directory into application storage, decode and validate `metadata.json`, render `content.md` in the local Markdown/LaTeX web bundle, resolve images from the copied `assets/` directory, use `toc` for section navigation, and render Markdown footnotes as links or popovers. It must preserve the package unchanged after successful validation.

# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, and `notes/state/fnmn.md`. Update the visible lifecycle and state diagrams in `APP_SPEC.md` before changing the flow. Use the `architect` skill first to define the user flow, state, events, adapters, and module ownership. Then use the `coding` skill to implement the smallest clear version in the existing files. Keep the code readable from the top-level flow down into details. Do not add generic managers, speculative protocols, or new layers without a concrete second implementation.

Current code already has a Mac REST article preparer, a shared JSON article package, library persistence, article import, folders, block-by-block reading, section navigation, saved reading position, Continue from the most recently opened material, and an explicit read/unread mark. Search, Share to FNMN, mass source import, and the learning feed are not implemented.

`mac/pdf-book/README.md` and `fixtures/books/principles-of-deep-learning-theory/` define a ready PDF-book directory contract: `content.md`, `metadata.json`, `assets/`, and `validation.json`. This is not the JSON `ImportPackage` used for articles. Do not convert the book into HTML blocks or re-extract the table of contents from Markdown.

Next task: import that book directory into the current library on `master`. Read `metadata.json` and `validation.json`, accept the package only when `errors` is empty, copy the whole directory into Application Support, keep a pointer in the existing library snapshot and `LibraryFile` path, and open the book from `toc`, `content.md`, local assets, formulas, and Markdown footnotes. Use native SwiftUI controls and keep IO in `LibraryFile` or a small existing-style adapter. Do not start search, sharing, YouTube, synchronization, or the learning feed in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

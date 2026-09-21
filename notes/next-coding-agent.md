# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, and `notes/state/fnmn.md`. The capture graph is already drawn in `APP_SPEC.md`. Implement the next node on that graph, not a side path. Use the `coding` skill. Keep the code readable from the top-level flow down into details. Do not add generic managers, speculative protocols, or a second library for Share.

Current code already has article JSON import, PDF-book directory import, folders on article packages, library search over catalog fields, block reading, book reading, saved position, Continue, and an explicit read/unread mark. Source classification, albums for every material, the single add field, Share Extension, the Markdown capture package, and the video reader are not implemented.

Next task: classify a URL or file as Web, arXiv, YouTube, X, Substack, ChatGPT, or PDF. Store album membership by material id, including books, with create, rename, and drag that adds a card to an album without removing it from others. Replace the separate add buttons with one add sheet: a link or a document. Send a web article through the existing Mac article route into the Web album. Stop other sources with an explicit error until their adapter exists. Do not build the Share Extension, the Markdown package, or the video player in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

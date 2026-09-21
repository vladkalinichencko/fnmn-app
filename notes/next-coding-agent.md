# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, and `notes/state/fnmn.md`. Update the visible lifecycle and state diagrams in `APP_SPEC.md` before changing the flow. Use the `architect` skill first to define the user flow, state, events, adapters, and module ownership. Then use the `coding` skill to implement the smallest clear version in the existing files. Keep the code readable from the top-level flow down into details. Do not add generic managers, speculative protocols, or new layers without a concrete second implementation.

Current code already has article JSON import, PDF-book directory import, folders, library search over catalog fields, block-by-block article reading, book reading from `toc` and local Markdown/KaTeX, saved position, Continue from the most recently opened material, and an explicit read/unread mark. Share to FNMN, mass source import, YouTube, synchronization, and the learning feed are not implemented.

Next task: add Share to FNMN for links from Safari, YouTube, Twitter, Substack, ChatGPT, and arXiv through one shared entry. Keep IO in existing adapters. Do not start mass YouTube import, synchronization, or the learning feed in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

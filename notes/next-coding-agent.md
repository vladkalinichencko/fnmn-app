# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `AGENTS.md`, `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, and `notes/state/fnmn.md`. Update the visible lifecycle and state diagrams in `APP_SPEC.md` before changing the flow. Use the `architect` skill first to define the user flow, state, events, adapters, and module ownership. Then use the `coding` skill to implement the smallest clear version in the existing files. Keep the code readable from the top-level flow down into details. Do not add generic managers, speculative protocols, or new layers without a concrete second implementation.

Current code already has a Mac REST article preparer, a shared document package, JSON library persistence, article import, folders, block-by-block reading, section navigation, saved reading position, and one editable note per block. Search, Share to FNMN, mass source import, and the learning feed are not implemented.

Next task: finish the first article-reader slice. Make `Continue` select the most recently opened material, add an explicit read/unread state, and keep those decisions in the existing library state and persistence path. Use native SwiftUI controls and keep IO in `LibraryFile` or the existing client adapters. Do not start search, sharing, YouTube, PDF, synchronization, or the learning feed in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

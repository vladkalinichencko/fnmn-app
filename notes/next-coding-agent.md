# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, and `notes/state/fnmn.md`. The capture graph is in `APP_SPEC.md`. Implement the next node on that graph. Use the `coding` skill. Keep IO in the existing Mac client and `LibraryFile`. Do not add a second library, a manager, or a protocol for one caller.

Current code classifies Web, arXiv, YouTube, X, Substack, ChatGPT, and PDF. Albums are stored by material id, can be created and renamed, and accept dragged articles or books without removing older membership. One add sheet takes a link or a document. A web article uses the existing Mac article route and lands in Web. A book folder lands in PDF. Other sources stop with an explicit error. Share Extension, the Markdown capture package, and the video reader are not implemented.

Next task: add a Share Extension that receives a URL from Safari, YouTube, X, Substack, ChatGPT, or arXiv and hands it to the same capture route as the add sheet. Do not prepare Markdown or play video in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

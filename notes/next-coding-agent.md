# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, and `notes/state/fnmn.md`. The capture graph is in `APP_SPEC.md`. Implement the next node on that graph. Use the `coding` skill. Keep IO in the existing Mac client and `LibraryFile`. Do not add a second library, a manager, or a protocol for one caller.

Current code classifies Web, arXiv, YouTube, X, Substack, ChatGPT, and PDF. Albums are stored by material id. One add sheet takes a link or a document. A web article uses the existing Mac article route and lands in Web. A book folder lands in PDF. Other sources stop with an explicit error. Share opens the app on that same add sheet with the shared link. The Mac still returns HTML blocks for a web article, not Markdown. The video reader is not implemented.

Next task: make the Mac return one text package for a web article: title, author, original link, and Markdown with LaTeX. Read that package in the existing Markdown reader and open the original with a separate action. Do not build arXiv, X, Substack, ChatGPT, or the video player in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

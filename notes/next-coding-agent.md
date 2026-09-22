# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, `notes/state/fnmn.md`, and `notes/research/web-article.md`. Use the `coding` skill. A download is one explicit state chain, not loading flags. Keep IO in the Mac adapter and `LibraryFile`.

Web article text is Markdown laid out in SwiftUI. Images and ordinary video are files in that layout. A `figure` that is not just a picture, and an iframe, are an `fnmn-interactive` block. The reader opens that URL in its own WKWebView, hides the rest of the page when a selector is present, and leaves the nodes in the document. Display math stays LaTeX in the Markdown. `mac/html_markdown.py` performs the translation. `import_web_article` downloads picture and video files. A missing one fails the import. The book reader still scrolls its Markdown in one WKWebView. An article package without `body` still uses the block reader.

Next task: draw display math in the SwiftUI article column, left-aligned, from the `$$` blocks already in the package. The Distill check lives in `mac/tests/test_distill.py`. Do not build the YouTube player in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

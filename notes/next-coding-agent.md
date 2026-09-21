# Prompt for Grok

Continue the FNMN iPhone/iPad app in this repository.

Read `APP_SPEC.md`, `notes/plan.md`, `notes/tasks.md`, `notes/state/fnmn.md`, and `notes/research/web-article.md`. Use the `coding` skill. A download is one explicit state chain, not loading flags. Keep IO in the Mac adapter and `LibraryFile`.

Web article text is Markdown laid out in SwiftUI. Images, GIFs, and video stay files in that layout. An interactive subtree is an `fnmn-interactive` fragment shown as its own WKWebView at that spot, sized to the fragment. Do not nest it inside the book WKWebView. Display math is left-aligned. `mac/html_markdown.py` performs the translation. The live `/articles` route still returns JSON blocks. The book reader still scrolls its Markdown in one WKWebView.

Next task: when importing a web article, download the scripts and assets an interactive fragment needs, as `fetchingPage → fetchingAssets → saving`, and fail the import if a required file is missing. Do not build the YouTube player in this task.

When you finish, present the work in plain language using one short sentence: what you implemented, what now works, and what remains next. Do not give a process report, tables, skill commentary, or a long verification narrative unless the user asks.

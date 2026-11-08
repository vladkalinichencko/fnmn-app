# Source identity: four questions, the options

Four rules decide how a link becomes a material and what it is called. Each one has several homes today. This memo gives the options, what each costs, and what I would pick; the choice is the owner's.

None of these is a hot path except the app's catalog build, and that one already memoizes per host.

## 1. Which kind a URL is

The app routes a pasted link to a screen; the server picks an adapter. Today: `CaptureRoute.source(for:)` and `CaptureSource` in the app, `sources.source_kind` and `NAMES` on the server, and neither knows everything the other does — the app has no `claude` or `notebook`, the server has no `instagram`.

**A. The server decides; the app reads the kind.** The app sends the URL; the server answers with the kind it used, and a delivery carries it.
Cost: an offline link has no kind until the Mac sees it, and the link card has to show "unknown" for a while.
Buys: one table, one place to add a host, no drift, no fixture to keep in sync.

**B. One host table as data, read by both.** A JSON file in the repo maps a host pattern to a kind; the app bundles it, the server imports it.
Cost: a small loader on each side and a rule that the app's copy is regenerated with the build.
Buys: offline routing works, and a new host is one edit in one file. The loader is a dictionary lookup; no measurable cost.

**C. Two tables, one fixture of addresses both are tested against.** What the YouTube parser does today after `57f5af7`.
Cost: a new host still needs two edits, and the test only fires when someone runs it.
Buys: no new machinery, and drift is caught at test time rather than by a user.

**Pick:** B if you accept a data file plus two loaders; C if you want the smallest change now. A is the cleanest for the server but makes the app's link card weaker offline.

## 2. Who publishes the page

The blog, channel or author a material belongs to. Today: `publisher_of` reads the live page (the section above the article, its front page, `og:site_name`); `collect/browser_library.source_for` guesses from a saved URL's path; `SourceIndex` in the app uses the saved catalog and the sources other materials declared.

**A. The server is canonical; the app falls back.** The server already writes `material.source` into the delivery. The app reads it, and `SourceIndex` answers only when it is absent — a link that has not reached the server, or a material prepared before the field existed.
Cost: almost none; the field exists and the app already has the fallback.
Buys: one implementation over the real page, no guessing from a path.

**B. The app owns it.** Drop `publisher_of`; the app resolves from the catalog.
Cost: the live page's section and `og:site_name` are lost; a site with no catalog entry falls back to its host name.
Buys: one implementation, fully offline.

**C. Both, as today.** Cost: two answers that can disagree, and a saved-path heuristic that no fixture covers.

**Pick:** A. It keeps the better answer and removes the duplicate without taking anything away.

## 3. The title of a material

Today: `page_article._title` (a heading from the DOM against `og:title`), `html_markdown` (first `h1` or the article root), `article.document` (`<title>`), and `package._document_package` (first heading in the Markdown, then the page title). Four fallback orders.

**A. One function over the page and its Markdown.** Order, written once: the first `h1` inside the article, `og:title`, `<title>`, the URL's last segment.
Cost: one function and a handful of fixtures; the adapters stop choosing.
Buys: the tile's title no longer depends on which branch found the article.

**B. Markdown only.** The title is the first heading of the text.
Cost: a page with no heading falls back to the URL for every adapter.
Buys: the simplest rule; one source.

**Pick:** A. B is tempting, but a page whose heading is an image would lose its name.

## 4. The delivery file name

Today `package.delivery_name(material_id)` hashes the id; `prepare_browser_library._delivery` hashes the URL. For a link they differ (`https://…` against `link:https://…`).

**A. The material id everywhere.** One function; the prepare script calls it.
Cost: one line; old prepared files keep their names because the app stores the name it read, and nothing recomputes them.
Buys: one rule, and a test that both writers agree.

**B. The URL everywhere.** Cost: a redirect changes the name; links that differ only by fragment already dedupe to one material, so the name would move under it. Not worth it.

**Pick:** A.

## What each costs in code

| Choice | New code | Deleted code | Risk |
|---|---|---|---|
| 1B shared host table | ~40 lines (two loaders, one JSON) | ~30 (two tables) | low: lookup by host |
| 1C fixture only | ~15 lines (test) | 0 | low |
| 2A server canonical | ~5 lines (app guard) | ~40 (path heuristic) | low: old materials keep the fallback |
| 3A one title function | ~25 lines | ~50 (four fallbacks) | medium: fixtures decide |
| 4A id names | 1 line | ~5 | low |

If you pick, the mechanical parts follow in one commit each, on the single unification branch.

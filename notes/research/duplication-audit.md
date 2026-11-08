# Code duplication audit

Every entry names both sites, so the claim can be checked without trusting this note. Read: `Sources/FNMNCore` (25 files), `App/FNMN` (48), `App/Share`, `App/Activity`, `server` (44 Python modules), and the unmerged `social-digest` branch (48 files against `origin/master`).

**The short version.** The app answers "which source does this page belong to" in three places with two different taxonomies, names a file from an id in three shapes, appends a journal line in two ways, and spells "a screen is loading" as six enums. The server writes a delivery archive in two modules, hashes asset names in four, drives yt-dlp in three, and runs two copies of the OCR loop. The digest branch added a second copy of four of those and brought its own card, stack, and search.

## Naming and identity

**1. Which source a page belongs to.** `CaptureRoute.source(for:)` (`Sources/FNMNCore/CaptureRoute.swift:8`) classifies a URL into `CaptureSource`; `source_kind` (`server/sources.py:18`) does the same into the server's `NAMES` keys; `SourceIndex` (`Sources/FNMNCore/SourceIndex.swift`) answers a third question — the publisher a saved link came from — and `publisher_of` (`server/publisher.py:29`) plus `collect/browser_library.py:65 source_for` answer that one twice more, once against the live page and once against the saved catalog. The taxonomies already disagree: `CaptureSource` has no `claude` and no `notebook`, `NAMES` has no `instagram`, and only the Swift table treats `youtu.be` and `twitter.com` as first-class. A link the app sends as `web` can be handled by the server's `claude` adapter and come back with an id the app's route never predicted.

*One home:* one declaration of the host table per side of the wire, generated from one list or returned by the server, so the app never re-derives a kind the server owns. `SourceIndex` and `publisher_of` answer a different question and should stay separate — but `collect/browser_library.source_for` is the offline half of `publisher_of` and can call it.

**2. YouTube video id.** `YouTube.videoID(in:)` (`Sources/FNMNCore/YouTube.swift:4`), `video_id_from_url` (`server/adapters/youtube.py:74`), and a third inline special case in `canonical_url` (`server/collect/browser_library.py:46`, which also rewrites the URL, not just reads the id). The two regex/id-shape rules match today; three copies means one of them will accept `watch?v=` while another does not.

*One home:* the server's parser is the contract; the Swift copy is needed only because `SourceIndex.key` groups links offline. Give it a test that runs both over one list of URLs.

**3. Delivery file name.** `delivery_name` (`server/package.py:142`), a second identical copy (`server/collect/reparse_library.py:89`), `_delivery` (`server/collect/prepare_browser_library.py:89`), and `LibraryFile.deliveryName` (`Sources/FNMNCore/LibraryFile.swift:384`). The prepare script hashes `row["url"]`; the other three hash the material id. For a link they differ (`https://…` against `link:https://…`), so the same material has two legal archive names depending on which writer made it. Nothing breaks today because the app stores the name it read, but any future writer that recomputes the name creates a second archive for one material.

*One home:* `package.delivery_name`, imported by both collect scripts; the prepare script passes the material id it already builds. Across the wire it stays a contract, and the existing `DeliveryArchiveTests` should pin the rule on the Swift side.

**4. Id to file or folder name.** `base64` with `/` → `_` for an article folder and its cover (`LibraryFile.swift:739`), `/` → `-` for a digest folder (`DigestFile.swift:105`), `sha256` hex for a delivery (three Python sites). Three encodings of one idea, in two files that already have a shared audience.

*One home:* one small `FileNames` enum in `FNMNCore` with three named functions, so a new id shape has one place to land.

## Storage mechanics

**5. The JSONL journal.** `LibraryFile.appendJournal` (`LibraryFile.swift:451`) creates `state/`, encodes one JSON object per line, appends under `NSFileCoordinator`, and compacts past 2000 lines. `DigestFile.append` (`DigestFile.swift:79`) creates `digest-state/`, encodes one object per line, and appends to `<device>.jsonl` with a `FileHandle`, without coordination. Same file format, same device-name convention, two writers with different safety guarantees — the digest one is the weaker, and it writes into the same iCloud folder.

*One home:* a `JournalFile` actor in `FNMNCore` parameterised by folder name, element type, and compaction policy, used by both. The digest needs no compaction, which is a parameter, not a second writer.

**6. Path containment.** `LibraryFile.contained` (`LibraryFile.swift:627`) refuses an empty path, a leading `/`, or any path containing `..`; `DigestFile.check` (`DigestFile.swift:109`) refuses an empty path, a leading `/`, or a `..` path *part*. So `a..b.png` is refused by one and accepted by the other. Two rules for "a name inside a package may not climb out", and they already differ.

*One home:* the stricter function, in `FNMNCore`, called by both, with one test over the same list of hostile paths.

**7. Pending writes and their flush.** `LibraryModel` holds `places`, `progressWrite`, `progressUnsaved` and flushes in `saveProgress()`; `DigestModel` holds `pending`, `indexSave`, and flushes in `settle()` / `writePending()`. Both debounce a save, both requeue on failure (`pending = events + pending` in both), both are flushed when the app leaves the foreground. The mechanism is the same; only the payload and the delay differ.

*One home:* a small `PendingWrites<Element>` helper (append, debounce, flush, requeue), leaving each model to say what one element is.

**8. Load state.** `LibraryLoadState` (`LibraryModel.swift:17`) and `DigestLoadState` (`DigestModel.swift:5`) are the same four cases with the same names. `EmbedPhase`, `CropPhase`, `Poster`, `ArticleText`, and `ConnectionCheck` are the same shape with one case carrying a value or an error. Six enums describe "nothing yet / working / ready / failed", and each screen re-implements the switch over it.

*One home:* `enum LoadState<Value>` with `idle, loading, ready(Value), failed(String)`, plus the one `ContentUnavailableView` that draws the failure and its retry. `ArticleText` earns its own type because two ready values exist; the rest do not.

## Library queries and grouping

**9. Bucket by a key, keep first-seen order.** `LibraryQueries.groups(by:)` (`LibraryQueries.swift:54`) builds `order`/`names`/`membersByGroup`; `LibraryQueries.arrange` (`LibraryQueries.swift:212`) builds `order`/`names`/`members` and sorts the same keys, months descending, the rest by localized name; `DigestPackage.sections` (`Digest.swift:250`) builds `order`/`groups`; `SourcesScreen.folders(of:)` (`SourcesScreen.swift:84`) filters per folder; `StoredAnnotations.merging` (`AnnotationMigration.swift`) builds the same order-then-buckets loop for paragraphs. Five copies of one algorithm, and the sorting rule for month keys is written twice.

*One home:* `orderedBuckets<Element>(_ items: [Element], by key: (Element) -> (key: String, name: String)?) -> [(key, name, [Element])]` in `FNMNCore`, with the caller choosing the final sort. `albumSummaries` and `groups` then also share one `AlbumSummary` construction instead of two.

**10. Two search normalisations.** `LibraryQueries.search` folds case, diacritics and width (`ArticleEntry.folded`); `DigestPackage.posts(matching:)` lowercases only. Typing `café` finds an article and misses a post; typing `Cafe` misses both. The two tabs answer the same question with two rules.

*One home:* the folding helper, already in `ArticleEntry`, used by both.

## Markdown interpretation

**11. Splitting Markdown into blocks.** `ArticleBody.rawBlocks` (`ArticleBody.swift:29`) walks lines, keeps fences and `$$` regions whole, treats a blank line as a boundary, and drops thematic breaks. `SpeedText.segments(of:)` (`SpeedText.swift:167`) walks lines, keeps fences and `$$` regions whole, treats a blank line as a boundary. A fix to one (a `~~~` fence, a `$$` that opens and closes on one line) does not reach the other, and speed reading then reads different paragraphs than the column shows.

*One home:* the splitter in `ArticleBody`, with `SpeedText` calling it and mapping its pieces to tokens.

**12. "Is `$…$` a formula or a price".** `MarkedMarkdown.isPrice` (`MarkedMarkdown.swift:89`) says a formula is prose when it has no TeX punctuation and holds a word of three or more letters. `SpeedText.isRich` (`SpeedText.swift:188`) says the opposite side of the same test with the same two conditions, one negated. The renderer and the speed reader can disagree about the same paragraph.

*One home:* one predicate over the inner text, in `FNMNCore`, used by both.

## The digest branch's views

**13. One post card, three drawings.** `PostCard` draws author + handle + network/time, the text, the media, and an open-in-network button on a plate. `ThreadScreen.parentCard` (`ThreadScreen.swift:43`) draws a smaller author + handle + text + open button on a plate; `ThreadScreen.comments` (`:80`) draws author + text + open button on a plate; `SourcesScreen.row` (`:38`) draws a name + detail + trailing label on a plate. Four hand-built variants of one row, each with its own font sizes.

*One home:* `PostCard` with parameters (compact, showsContext, opensThread) plus one `PlateRow` for the non-post rows; the four call sites keep their data, lose their layout.

**14. Two navigation stacks.** `RouteStack` (`Shell.swift:139`) binds `[Route]`, builds a `NavigationStack`, maps routes, hides the tab bar on the routes that own the screen. `DigestStack` (`DigestScreen.swift:90`) binds `[DigestRoute]`, builds a `NavigationStack`, maps routes, hides the tab bar for a thread. The second is the first with a different generic.

*One home:* one generic `RouteStack<Route: Hashable>` taking a destinations closure and a `hidesTabBar` predicate.

**15. Formatting a duration.** `PostCard.length` (`PostCard.swift:188`) writes `m:ss` by hand; `CueRow` (`VideoReaderView.swift`) formats `Duration.seconds(...)` with `.time(pattern:)`. Two answers for "seconds as a clock", one of which rounds and one of which truncates.

*One home:* one `Duration` formatting helper; `.time(pattern:)` already covers the hour case.

**16. Network display names.** `PostCard.network(_:)` maps `x`/`telegram`/`instagram` to display names; `SourcesScreen` checks `network == "telegram"` to say "Channel" instead of "Account"; the server's `DigestPackage.Source.network` carries the raw id. A fourth network means edits in three places.

*One home:* a `DigestNetwork` enum in `FNMNCore`, decoded from the raw string, carrying name and account kind.

## Server: pages

**17. Parse a page, ignoring its XML declaration.** `html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))` appears at `adapters/article.py:39`, `adapters/article.py:78` (with `base_url`), `adapters/html_markdown.py:32`, and `publisher.py:46`. Four copies of a six-token incantation; a fifth parser added later will copy it again.

*One home:* `page_document(source, base_url=None)` next to `article_markdown`.

**18. Where the title comes from.** `page_article._title` picks a heading from the DOM against `og:title` and `<title>`; `html_markdown.article_markdown` falls back to the first `<h1>` or to `article_root`; `article.document` takes `<title>`; `package._document_package` prefers `first_heading(body)` and only then `page_title(document.title)`. Four places decide a material's name, each with a different fallback order, so the title a tile shows depends on which parser branch found the article.

*One home:* one `title(for:)` that takes the DOM and the written Markdown and returns one answer, with the fallbacks written once.

**19. The publisher of a page.** `server/publisher.py` resolves it from the live page (section above the article, else front page, plus `og:site_name`); `collect/browser_library.source_for` resolves it from the saved URL's path alone; `SourceIndex` resolves it in the app from the catalog and the declared sources. Three models of "who owns this page", and the app's answer can name a different source than the server's for the same article.

*One home:* the server writes `material.source` for every delivery (it already does when it can) and the app's `SourceIndex` only fills gaps for materials imported before that; the offline catalog's `source_for` should call `publisher_of`'s path logic instead of restating it.

## Server: Markdown repair

**20. `_punctuation`.** Identical function, `server/markdown.py:110` and `server/adapters/html_markdown.py:274`.

**21. Where a bold run may open or close.** `html_markdown._joined` merges adjacent runs of one emphasis and inserts a space around marks next to punctuation, using `OPENING_PUNCTUATION`/`CLOSING_PUNCTUATION` from `markdown.py`. `markdown._spaced_bold` repairs `**a****b**` and the same punctuation cases on the finished text. `normalize()` runs afterwards on the same Markdown, so the repair has two homes and runs twice; `**Eyes:**green` is handled in both.

*One home:* the Markdown writer emits marks already paired (it knows the neighbours), and `markdown.py` keeps only the repair that no writer can avoid (a `****` that came from input the app never produced).

## Server: assets and archives

**22. Asset path from a name or a body.** `assets/{sha256[:16]}{suffix}` in `html_markdown._stored` (`:172`) and `arxiv._graphic` (`:231`); `assets/interactive-{sha256[:16]}.html` in `claude._page` (`:127`) and `chatgpt._app` (`:153`). Four copies, two naming conventions, one idea.

*One home:* `assets.path(for: blob_or_name, suffix=..., prefix=None)` in `package.py`, which both adapters already import.

**23. The USTAR writer.** `package._add` (`:196`) and `digest.build._add` (`:120`) are the same eight lines. `package.write_delivery` writes USTAR and then renames `*.incoming` over the target; `digest.build._write` writes USTAR and then renames `*.tar.part` over the target. One format, two writers, two temporary-name conventions, both aimed at the same iCloud folder.

*One home:* `write_delivery` with a file-source variant (the digest copies media from disk rather than holding bytes), so the digest builder calls it instead of assembling its own archive.

## Server: network drivers

**24. Driving yt-dlp.** `collect/playlist_export.dump_json_lines` (`:37`) runs the CLI with `--dump-json` and parses JSON lines; `collect/watchlater_urls.build_command` (`:27`) builds the same command with the same cookie flags; `collect/browser_library` runs `subprocess.run` twice (`:137`, `:145`) with `--dump-single-json` and `--print`. Cookie flags exist in two shapes (`auth_flags` and an inline splice). Error handling repeats "last non-empty stderr line" three times.

*One home:* `collect/ytdlp.py` with `entries(url, cookies...)`, `info(url)`, `print_field(url, template)`, and the one error message. The adapters' direct `yt_dlp` import is a different layer (library, not CLI) and can stay.

## Server: digest data

**25. A post in four spellings.** `digest/x._context_post` builds a dict with snake-case keys, `Post` (`digest/store.py:26`) is the dataclass, `store.wire` renames fields to camelCase by hand, `wire_context` renames the nested post again with `post.get("posted_at") or post.get("postedAt")`, and `DigestPackage.ContextPost` decodes it in Swift. Adding one field to a post means editing four places, and forgetting `wire_context` silently drops it from quoted posts only.

*One home:* `Post` with an explicit `to_wire()` (one function, no second rename), and `ContextPost` built from the same function with a field subset.

**26. Image size at build time.** `digest/store.image_size` (`:162`) reads PNG/GIF/JPEG headers so each card can lay itself out before decoding; `ImageFiles.headerSize` (`App/FNMN/Store/ImageFiles.swift`) reads the same headers on the phone with ImageIO. Two header readers for one question, and the shipped size is advisory only.

*One home:* the phone can read the header of a file it has already downloaded; the server can keep the size as a fallback for formats ImageIO will not open. Today both exist and neither is declared the source of truth.

## Server: pdf-book

**27. The OCR job loop.** `run-footnote-ocr.py` and `run-formula-ocr.py` load the same model with the same prompt, iterate `jobs`, skip keys already in `overrides`, time the call, write `<page>-<key>.md` and `.json` with the same metric fields, and rewrite the overrides file after each item. Only the selector (`select_footnote` against `select_formula`) differs.

*One home:* one `ocr_jobs.py` with `run(jobs, selector, output, model)`, leaving each script to say which issues it collects and how it narrows the answer.

**28. Stripping OCR grounding.** `GROUNDING` and the "join the text between grounding blocks" loop in `math_issues.select_formula` (`:52`) and `run-footnote-ocr.markdown` (`:16`); `assemble-book.read_ocr` (`:48`) parses the same blocks with the same regex shape. Three readers of one OCR output format.

*One home:* `grounding.py` — `strip(text)` for the two selectors and `blocks(text)` for the assembler.

**29. Chapter numbers.** `export-app-book.NUMBER`/`clean_heading` (`:17`, `:35`) and `assemble-book.heading_similarity.clean` (`:34`) both strip `12.3`/`A.4`/`∞` prefixes from a heading, with two different regexes of the same intent.

*One home:* one `strip_numbering(title)`, since the two must agree or a heading will match in one pass and not the other.

## Tests and unused code

**30. Test web double.** `FakeWeb` in `server/tests/test_digest_sources.py:22` re-implements `tests/fakes.py:4 web(...)`, which the other five test modules use. The digest one also subclasses the `NamedTuple`, which the shared helper avoids.

**31. The Activity target has no producer.** `ImportActivityAttributes` and `ImportActivityWidget` (with `Ring`, `ShareDone`) are a progress UI, but `ImportActivity` now uses `BGContinuedProcessingTask` and never starts an Activity; nothing calls `Activity<ImportActivityAttributes>`. It is a second, unused drawing of a job's share done, next to `ProgressLine`/`JobStatus`.

## Already single, and worth keeping

`LibraryQueries` is built once in `LibraryModel.refreshQueries` and the lint rule plus `HotPathGuardTests` enforce it. `DeliveryArchive` is the only reader of a delivery, for articles and digests alike. `ItemGrid`, `ItemActions`, `OpenOriginalButton`, `LibrarySection`, `ScreenSearch`, `plate`, `Loading` and `FileImage` are shared by every screen that needs them. On the server, `Web`, `Report`, `ImportFailure`, `markdown.normalize`, `stable_id` and `iso` each have one home. The test tar writer is shared (`writeTar` is used by both delivery and digest tests), which is the shape to copy.

The five reducers (`importReduce`, `dialogReduce`, `readerReduce`, `videoReduce`, `plateReduce`) and the five coordinators that own them are not duplication: same skeleton, different state, different effects. Merging them would produce one generic machine nobody can read.

## Where to start

1. **Delivery name and archive writer** (items 3, 23) — the smallest blast radius and the one place where two answers already exist for one question.
2. **Classification table** (items 1, 2, 19) — the app/server taxonomy has already drifted; this is the one that produces wrong behavior, not just extra code.
3. **Journal writer and path containment** (items 5, 6) — both sit under iCloud with two safety levels.
4. **Grouping and Markdown splitting** (items 9, 11, 12) — pure functions, cheap to merge, and each has a test seam already.
5. **Load state and search folding** (items 8, 10) — visible to the reader, mechanical to change.
6. **Digest card, stack, and post wire shape** (items 13, 14, 25) — the branch is unmerged, so this is cheapest before it lands.

Each merge needs the guard from `AGENTS.md`: a source test that fails when a second implementation appears (a second `sha256(…)+".tar"`, a second `LibraryQueries(`-style construction, a file that renames a post field by hand), not a test of the one call site that was cleaned up.

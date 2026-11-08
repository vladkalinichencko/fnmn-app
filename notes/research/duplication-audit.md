# Code duplication audit

Every entry names both sites, so the claim can be checked without trusting this note. Read: `Sources/FNMNCore` (25 files), `App/FNMN` (48), `App/Share`, `App/Activity`, `server` (44 Python modules), and the unmerged `social-digest` branch (48 files against `origin/master`).

**The short version.** The app answers "which source does this page belong to" in three places with two different taxonomies, names a file from an id in three shapes, appends a journal line in two ways, and spells "a screen is loading" as six enums. The server writes a delivery archive in two modules, hashes asset names in four, drives yt-dlp in three, and runs two copies of the OCR loop. The digest branch added a second copy of four of those and brought its own card, stack, and search.

## Naming and identity

**1. Which source a page belongs to.** `CaptureRoute.source(for:)` (`Sources/FNMNCore/CaptureRoute.swift:8`) classifies a URL into `CaptureSource`; `source_kind` (`server/sources.py:18`) does the same into the server's `NAMES` keys; `SourceIndex` (`Sources/FNMNCore/SourceIndex.swift`) answers a third question — the publisher a saved link came from — and `publisher_of` (`server/publisher.py:29`) plus `collect/browser_library.py:65 source_for` answer that one twice more, once against the live page and once against the saved catalog. The taxonomies already disagree: `CaptureSource` has no `claude` and no `notebook`, `NAMES` has no `instagram`, and only the Swift table treats `youtu.be` and `twitter.com` as first-class. A link the app sends as `web` can be handled by the server's `claude` adapter and come back with an id the app's route never predicted.

*One home:* one declaration of the host table per side of the wire, generated from one list or returned by the server, so the app never re-derives a kind the server owns. `SourceIndex` and `publisher_of` answer a different question and should stay separate — but `collect/browser_library.source_for` is the offline half of `publisher_of` and can call it.

*Decided 2026-11-08:* the two tables stay. The server and the app model different things and share only the wire format — see AGENTS.md, "Across the boundary".

**2. YouTube video id.** `YouTube.videoID(in:)` (`Sources/FNMNCore/YouTube.swift:4`), `video_id_from_url` (`server/adapters/youtube.py:74`), and a third inline special case in `canonical_url` (`server/collect/browser_library.py:46`, which also rewrites the URL, not just reads the id). The two regex/id-shape rules match today; three copies means one of them will accept `watch?v=` while another does not.

*One home:* the server's parser is the contract; the Swift copy is needed only because `SourceIndex.key` groups links offline. Give it a test that runs both over one list of URLs.

*Partly closed in 57f5af7:* one fixture of addresses runs through both parsers. The two implementations stay until question 1 in `notes/research/source-identity.md` is answered.

**3. Delivery file name.** `delivery_name` (`server/package.py:142`), a second identical copy (`server/collect/reparse_library.py:89`), `_delivery` (`server/collect/prepare_browser_library.py:89`), and `LibraryFile.deliveryName` (`Sources/FNMNCore/LibraryFile.swift:384`). The prepare script hashes `row["url"]`; the other three hash the material id. For a link they differ (`https://…` against `link:https://…`), so the same material has two legal archive names depending on which writer made it. Nothing breaks today because the app stores the name it read, but any future writer that recomputes the name creates a second archive for one material.

*One home:* `package.delivery_name`, imported by both collect scripts; the prepare script passes the material id it already builds. Across the wire it stays a contract, and the existing `DeliveryArchiveTests` should pin the rule on the Swift side.

*Closed in 854f615:* the prepare script names a link archive `delivery_name("link:<url>")` and an article archive `delivery_name(stable_id("article", url))`; a legacy URL-named file is renamed once instead of refetched; `test_prepare` pins both.

**4. Id to file or folder name.** `base64` with `/` → `_` for an article folder and its cover (`LibraryFile.swift:739`), `/` → `-` for a digest folder (`DigestFile.swift:105`), `sha256` hex for a delivery (three Python sites). Three encodings of one idea, in two files that already have a shared audience.

*One home:* one small `FileNames` enum in `FNMNCore` with three named functions, so a new id shape has one place to land.

## Storage mechanics

**5. The JSONL journal.** `LibraryFile.appendJournal` (`LibraryFile.swift:451`) creates `state/`, encodes one JSON object per line, appends under `NSFileCoordinator`, and compacts past 2000 lines. `DigestFile.append` (`DigestFile.swift:79`) creates `digest-state/`, encodes one object per line, and appends to `<device>.jsonl` with a `FileHandle`, without coordination. Same file format, same device-name convention, two writers with different safety guarantees — the digest one is the weaker, and it writes into the same iCloud folder.

*One home:* a `JournalFile` actor in `FNMNCore` parameterised by folder name, element type, and compaction policy, used by both. The digest needs no compaction, which is a parameter, not a second writer.

*Closed in 1261132:* `JSONLines` owns the line and the append; the library keeps its coordination and its generation, the digest its atomic first write.

**6. Path containment.** `LibraryFile.contained` (`LibraryFile.swift:627`) refuses an empty path, a leading `/`, or any path containing `..`; `DigestFile.check` (`DigestFile.swift:109`) refuses an empty path, a leading `/`, or a `..` path *part*. So `a..b.png` is refused by one and accepted by the other. Two rules for "a name inside a package may not climb out", and they already differ.

*One home:* the stricter function, in `FNMNCore`, called by both, with one test over the same list of hostile paths.

*Closed in 41ac307:* `PackagePath.isSafe` and `resolves`, with `PackagePathTests`. The media endpoint's name check guards a URL segment, not a package path, and stays.

**7. Pending writes and their flush.** `LibraryModel` holds `places`, `progressWrite`, `progressUnsaved` and flushes in `saveProgress()`; `DigestModel` holds `pending`, `indexSave`, and flushes in `settle()` / `writePending()`. Both debounce a save, both requeue on failure (`pending = events + pending` in both), both are flushed when the app leaves the foreground. The mechanism is the same; only the payload and the delay differ.

*One home:* a small `PendingWrites<Element>` helper (append, debounce, flush, requeue), leaving each model to say what one element is.

**8. Load state.** `LibraryLoadState` (`LibraryModel.swift:17`) and `DigestLoadState` (`DigestModel.swift:5`) are the same four cases with the same names. `EmbedPhase`, `CropPhase`, `Poster`, `ArticleText`, and `ConnectionCheck` are the same shape with one case carrying a value or an error. Six enums describe "nothing yet / working / ready / failed", and each screen re-implements the switch over it.

*One home:* `enum LoadState<Value>` with `idle, loading, ready(Value), failed(String)`, plus the one `ContentUnavailableView` that draws the failure and its retry. `ArticleText` earns its own type because two ready values exist; the rest do not.

*Partly closed in c50d948:* `LoadState` serves the library and the digest. `EmbedPhase`, `CropPhase` and `ConnectionCheck` still describe themselves, and each carries a different ready value.

## Library queries and grouping

**9. Bucket by a key, keep first-seen order.** `LibraryQueries.groups(by:)` (`LibraryQueries.swift:54`) builds `order`/`names`/`membersByGroup`; `LibraryQueries.arrange` (`LibraryQueries.swift:212`) builds `order`/`names`/`members` and sorts the same keys, months descending, the rest by localized name; `DigestPackage.sections` (`Digest.swift:250`) builds `order`/`groups`; `SourcesScreen.folders(of:)` (`SourcesScreen.swift:84`) filters per folder; `StoredAnnotations.merging` (`AnnotationMigration.swift`) builds the same order-then-buckets loop for paragraphs. Five copies of one algorithm, and the sorting rule for month keys is written twice.

*One home:* `orderedBuckets<Element>(_ items: [Element], by key: (Element) -> (key: String, name: String)?) -> [(key, name, [Element])]` in `FNMNCore`, with the caller choosing the final sort. `albumSummaries` and `groups` then also share one `AlbumSummary` construction instead of two.

*Partly closed in bf51e6d:* `OrderedGroups` serves `groups`, `arrange` and `sections`. `SourcesScreen.folders` and the legacy-annotation merge still bucket on their own.

**10. Two search normalisations.** `LibraryQueries.search` folds case, diacritics and width (`ArticleEntry.folded`); `DigestPackage.posts(matching:)` lowercases only. Typing `café` finds an article and misses a post; typing `Cafe` misses both. The two tabs answer the same question with two rules.

*One home:* the folding helper, already in `ArticleEntry`, used by both.

*Closed in ce79d59:* `TextFold.folded`; both searches call it, and a test finds `café` from `cafe`.

## Markdown interpretation

**11. Splitting Markdown into blocks.** `ArticleBody.rawBlocks` (`ArticleBody.swift:29`) walks lines, keeps fences and `$$` regions whole, treats a blank line as a boundary, and drops thematic breaks. `SpeedText.segments(of:)` (`SpeedText.swift:167`) walks lines, keeps fences and `$$` regions whole, treats a blank line as a boundary. A fix to one (a `~~~` fence, a `$$` that opens and closes on one line) does not reach the other, and speed reading then reads different paragraphs than the column shows.

*One home:* the splitter in `ArticleBody`, with `SpeedText` calling it and mapping its pieces to tokens.

*Closed in 109841d:* `MarkdownParts.split`, with the heading and rule rules beside it; the tests pin a heading after text, a fence with blank lines and a `$$` block.

**12. "Is `$…$` a formula or a price".** `MarkedMarkdown.isPrice` (`MarkedMarkdown.swift:89`) says a formula is prose when it has no TeX punctuation and holds a word of three or more letters. `SpeedText.isRich` (`SpeedText.swift:188`) says the opposite side of the same test with the same two conditions, one negated. The renderer and the speed reader can disagree about the same paragraph.

*One home:* one predicate over the inner text, in `FNMNCore`, used by both.

*Closed in 4cae4d4:* `InlineMath.looksLikeProse`; `InlineMathTests` pins a price, a formula and the lone letter that is a variable.

## The digest branch's views

**13. One post card, three drawings.** `PostCard` draws author + handle + network/time, the text, the media, and an open-in-network button on a plate. `ThreadScreen.parentCard` (`ThreadScreen.swift:43`) draws a smaller author + handle + text + open button on a plate; `ThreadScreen.comments` (`:80`) draws author + text + open button on a plate; `SourcesScreen.row` (`:38`) draws a name + detail + trailing label on a plate. Four hand-built variants of one row, each with its own font sizes.

*One home:* `PostCard` with parameters (compact, showsContext, opensThread) plus one `PlateRow` for the non-post rows; the four call sites keep their data, lose their layout.

**14. Two navigation stacks.** `RouteStack` (`Shell.swift:139`) binds `[Route]`, builds a `NavigationStack`, maps routes, hides the tab bar on the routes that own the screen. `DigestStack` (`DigestScreen.swift:90`) binds `[DigestRoute]`, builds a `NavigationStack`, maps routes, hides the tab bar for a thread. The second is the first with a different generic.

*One home:* one generic `RouteStack<Route: Hashable>` taking a destinations closure and a `hidesTabBar` predicate.

*Closed in 6002fd7:* `RouteStack<Path, Root, Destination>`, `Route.hidesTabBar` and `DigestRoute.hidesTabBar`, with `RouteHidingTests`.

**15. Formatting a duration.** `PostCard.length` (`PostCard.swift:188`) writes `m:ss` by hand; `CueRow` (`VideoReaderView.swift`) formats `Duration.seconds(...)` with `.time(pattern:)`. Two answers for "seconds as a clock", one of which rounds and one of which truncates.

*One home:* one `Duration` formatting helper; `.time(pattern:)` already covers the hour case.

**16. Network display names.** `PostCard.network(_:)` maps `x`/`telegram`/`instagram` to display names; `SourcesScreen` checks `network == "telegram"` to say "Channel" instead of "Account"; the server's `DigestPackage.Source.network` carries the raw id. A fourth network means edits in three places.

*One home:* a `DigestNetwork` enum in `FNMNCore`, decoded from the raw string, carrying name and account kind.

*Closed in 9319bf4:* `DigestPackage.Network` carries the name, and `Source.Status` and `Context.Kind` became enums with it. The "Channel or Account" label is still a condition in `SourcesScreen`, now over an enum.

## Server: pages

**17. Parse a page, ignoring its XML declaration.** `html.fromstring(re.sub(r"^\s*<\?xml[^>]*\?>", "", source, count=1))` appears at `adapters/article.py:39`, `adapters/article.py:78` (with `base_url`), `adapters/html_markdown.py:32`, and `publisher.py:46`. Four copies of a six-token incantation; a fifth parser added later will copy it again.

*One home:* `page_document(source, base_url=None)` next to `article_markdown`.

**18. Where the title comes from.** `page_article._title` picks a heading from the DOM against `og:title` and `<title>`; `html_markdown.article_markdown` falls back to the first `<h1>` or to `article_root`; `article.document` takes `<title>`; `package._document_package` prefers `first_heading(body)` and only then `page_title(document.title)`. Four places decide a material's name, each with a different fallback order, so the title a tile shows depends on which parser branch found the article.

*One home:* one `title(for:)` that takes the DOM and the written Markdown and returns one answer, with the fallbacks written once.

*Closed in 2804ce1:* `material_title(title, body, fallback)`; the app only reads `material.title`, and `test_markdown` pins the order.

**19. The publisher of a page.** `server/publisher.py` resolves it from the live page (section above the article, else front page, plus `og:site_name`); `collect/browser_library.source_for` resolves it from the saved URL's path alone; `SourceIndex` resolves it in the app from the catalog and the declared sources. Three models of "who owns this page", and the app's answer can name a different source than the server's for the same article.

*One home:* the server writes `material.source` for every delivery (it already does when it can) and the app's `SourceIndex` only fills gaps for materials imported before that; the offline catalog's `source_for` should call `publisher_of`'s path logic instead of restating it.

*Closed in 7562c6e:* `Material.declaredSource` first, `SourceIndex` only when the server named none; `SourceNameTests` pins both.

## Server: Markdown repair

**20. `_punctuation`.** Identical function, `server/markdown.py:110` and `server/adapters/html_markdown.py:274`.

**21. Where a bold run may open or close.** `html_markdown._joined` merges adjacent runs of one emphasis and inserts a space around marks next to punctuation, using `OPENING_PUNCTUATION`/`CLOSING_PUNCTUATION` from `markdown.py`. `markdown._spaced_bold` repairs `**a****b**` and the same punctuation cases on the finished text. `normalize()` runs afterwards on the same Markdown, so the repair has two homes and runs twice; `**Eyes:**green` is handled in both.

*One home:* the Markdown writer emits marks already paired (it knows the neighbours), and `markdown.py` keeps only the repair that no writer can avoid (a `****` that came from input the app never produced).

## Server: assets and archives

**22. Asset path from a name or a body.** `assets/{sha256[:16]}{suffix}` in `html_markdown._stored` (`:172`) and `arxiv._graphic` (`:231`); `assets/interactive-{sha256[:16]}.html` in `claude._page` (`:127`) and `chatgpt._app` (`:153`). Four copies, two naming conventions, one idea.

*One home:* `assets.path(for: blob_or_name, suffix=..., prefix=None)` in `package.py`, which both adapters already import.

*Closed in dcdf2a4:* `asset_path(seed, suffix, prefix)`; the four adapters call it and the names are unchanged.

**23. The USTAR writer.** `package._add` (`:196`) and `digest.build._add` (`:120`) are the same eight lines. `package.write_delivery` writes USTAR and then renames `*.incoming` over the target; `digest.build._write` writes USTAR and then renames `*.tar.part` over the target. One format, two writers, two temporary-name conventions, both aimed at the same iCloud folder.

*One home:* `write_delivery` with a file-source variant (the digest copies media from disk rather than holding bytes), so the digest builder calls it instead of assembling its own archive.

*Closed in dcdf2a4:* `write_delivery_from(path, package, files)`; the builder lost its `_add`, `_add_path` and `os.replace`.

## Server: network drivers

**24. Driving yt-dlp.** `collect/playlist_export.dump_json_lines` (`:37`) runs the CLI with `--dump-json` and parses JSON lines; `collect/watchlater_urls.build_command` (`:27`) builds the same command with the same cookie flags; `collect/browser_library` runs `subprocess.run` twice (`:137`, `:145`) with `--dump-single-json` and `--print`. Cookie flags exist in two shapes (`auth_flags` and an inline splice). Error handling repeats "last non-empty stderr line" three times.

*One home:* `collect/ytdlp.py` with `entries(url, cookies...)`, `info(url)`, `print_field(url, template)`, and the one error message. The adapters' direct `yt_dlp` import is a different layer (library, not CLI) and can stay.

*Closed in 7aaea62:* `command`, `run`, `entries`, `parse_entries`, `info`, `field`, `last_line`; `test_ytdlp` covers the command order and the parsing.

## Server: digest data

**25. A post in four spellings.** `digest/x._context_post` builds a dict with snake-case keys, `Post` (`digest/store.py:26`) is the dataclass, `store.wire` renames fields to camelCase by hand, `wire_context` renames the nested post again with `post.get("posted_at") or post.get("postedAt")`, and `DigestPackage.ContextPost` decodes it in Swift. Adding one field to a post means editing four places, and forgetting `wire_context` silently drops it from quoted posts only.

*One home:* `Post` with an explicit `to_wire()` (one function, no second rename), and `ContextPost` built from the same function with a field subset.

*Partly closed in c01cb3e:* `media_errors` went into `wire` only, so the nested rename in `wire_context` still carries every context field by hand.

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

*Closed in 5554335:* `fake_web` calls `tests.fakes.web`.

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

## Second pass: the branch's later commits (2026-11-08)

Eleven commits landed after the first pass, `9319bf4..9fb771b`. One of the first audit's items closed (16, the network names), three other defects the branch had opened closed with it, and the same commits added new copies of three rules and left two comments saying the opposite of what the code does. Items 1–31 stand unless this section says otherwise, and line numbers are from `9fb771b`.

### Closed since the first pass

**The delivery loop** — not in the first audit, found while reading the branch: `LibraryImporter.readChangedDeliveries` and `DigestModel.take` each listed, downloaded, skipped and imported archives. `33aa33c` made `DeliverySync` the one loop and `LibraryDeliveries`/`DigestDeliveries` the two adapters. This is the shape the rest of this note asks for: one algorithm, two parameter sets, and the adapters keep only the policy that differs.

**`seen`/`hidden` were a second copy of `DigestIndex`** — a save could write the older set. They are computed from `index` now (`9319bf4`), so the copy cannot exist.

**Network, status and context kind were strings with a `default`** — `DigestPackage.Network`, `Source.Status` and `Context.Kind` are enums, so a fourth network fails to decode instead of drawing as "Quoting" (item 16).

**Save to Library did not record the engagement** — `DigestModel.save` is the one call that records `.saved`; see the AGENTS section for why the guard behind it is weaker than the register says.

### New duplication

**32. The context label, twice.** `PostCard.contextLabel` (`PostCard.swift:210`) switches reply, repost and quote to "Replying to", "Reposting", "Quoting"; `ThreadScreen.parentCard` (`ThreadScreen.swift:54`) writes the same three labels as a nested ternary and drops the handle. The icon switch beside it has no second copy, so only the words have drifted. One home: `Context.Kind.label(following: String?)`, with the card and the thread both calling it.

*Closed in 173f513:* `Context.Kind.action` holds the three words; the card keeps its sentence and the thread shows the words alone.

**33. The source table and its browser rule, twice.** `monitor.py:22` and `refresh.py:20` both declare `SOURCES = {"x": x, "telegram": telegram, "instagram": instagram}`, and both decide which networks open a browser (`monitor._run`, `refresh._collect`). The tuple is `("x", "instagram", "telegram")` in both, so Telegram now opens a profile it did not need before — a decision made by editing two copies. `reading.py` is the declared home of the source contract and should own the table and a `needs_browser(network)` beside it.

*Closed in 07d6196:* `monitor.SOURCES` is the only table and `refresh` imports it; `needs_browser` sits in `reading.py`, and a test asserts both modules share the one dict.

**34. The build hours, twice.** `build.BUILD_HOURS = (8, 20)` (`build.py:25`) decides `due()` and `next_build_time`; `fnmn-digest.sh:57,60` writes 8 and 20 into the launchd plist, and `:64` writes the trainer's 21. `digest_script_checks` proves every `Hour` has a `Minute`; it cannot see that the hours disagree with the builder, so changing one leaves the other firing at the old time.

*Closed in 07d6196:* the shell asks `digest.build` for the hours, and `digest_script_checks` fails a script that writes fixed builder hours.

**35. `DigestModel.refresh` writes digest files.** `DigestFile` documents itself as "the one writer of the digest files" (`DigestFile.swift:3`) and owns `check(path)` for every name a delivery brings. `refresh` (`DigestModel.swift:91`) creates `media/` and writes `refresh-<name>` into `digest.url(of:)` with `FileManager`, on the main actor, while the `DigestFile` actor may be evicting or replacing that same folder. A second writer of one folder is what the file's own doc forbids.

*Closed in ddcb859:* `DigestFile.saveMedia`; the model passes bytes and a name, and a test refuses `../x.jpg`.

**36. The cache is decoded three to four times per sync.** `load()` reads every `package.json` (`DigestModel.swift:183`), `take` reads them again for `unpacked` (`:194`), `evict(keeping:)` reads them a third time, and `sync` reads them once more after `take`. After `load()` the model already holds exactly the ids `unpacked` wants, and `evict` could take the list it is given.

*Partly closed in 173f513:* `load` reads only the index, `take` reuses `digests`, and the cache is read again only after an archive was taken. `evict` still lists it on the first new delivery.

**37. Two "is this file known" checks in `DigestDeliveries`.** `changed` builds `imported[file] = id` as a dictionary (`:271`), `add` re-asks with `contains(where:)` (`:287`). One rule, two shapes, O(1) against O(n). The index also exists twice during a sync — `DigestModel.index` and `DigestDeliveries.index` — and the model copies it back after the loop, which is the shadow copy the AGENTS section warns about.

*Closed in 173f513:* one `imported` map feeds `changed` and `add`; the index is still passed into the adapter and read back once.

**38. `service.digest_media` knows the store's layout.** `service.py:104` builds `digest/out/media/<name>`; `Store` owns `OUT` and `media_dir` (`store.py:17,88`). Moving the store leaves an endpoint that 404s every picture.

*Closed in 07d6196:* the endpoint asks `Store().media_dir`, and `test_a_picture_in_the_store_is_served` proves the path.

**39. Test support, copied.** `App/FNMNTests/DigestModelTests.writeTar` (`:62`) is a second 40-line USTAR writer beside `Tests/FNMNCoreTests/DeliveryArchiveTests.writeTar`; the package and app test targets cannot share code, so the copies cannot converge without a shared test-support target. In the server tests three modules define their own `post()` factory (`test_digest_store`, `test_digest_build`, `test_digest_refresh`) and two define their own ISO 8601 encoder. In `LibraryImporterTests` the same four-line `LibraryImporter.Write` closure is written four times (`:32`, `:49`, `:57`, `:74`) and could be one helper on the test class.

*Partly closed in 173f513 and 07d6196:* one `post()` factory in `fakes.py` and one `Published` helper. The tar writer stays in each target; sharing it needs a product both test bundles can import.

**40. The source-scan loop, three times.** `ServerLinkGuardTests`, `HotPathGuardTests` and `ArchitectureGuardTests.testWebViewsAppearOnlyInTheLiveCropAndThePlayer` each read every app file, split lines and collect hits. `AppSources` already shares the file list; one `AppSources.hits(of:excluding:)` would make the next guard one sentence.

**41. Pass-throughs.** `DigestModel.posts(matching:in:)` forwards to `DigestPackage.posts(matching:hidden:)`, and `PostCard.network(_:)` returns `name.name`. Both add a name without a decision.

*Closed in 173f513:* both deleted; the screen asks the package for its posts and the card reads `post.network.name`.

**42. Three closures that call one method.** `DigestScreen` spells `Task { await digests.sync(folder: library.cloudFolder) }` for Try Again, Refresh and the error row's Retry. One action that reads the folder in one place would keep the folder out of three view closures.

**43. Only the first delivery failure is shown.** `DeliverySync.run` returns every failure; `LibraryImporter.readChangedDeliveries` throws `.first` and drops the rest, while the digest joins all of them into `lastError`. The library's reader learns about one bad archive and never about the second.

*Closed in 173f513:* the library joins every failure, and `testEveryUnreadableDeliveryIsNamed` names both archives.

### AGENTS.md against the code

**The new "one writer" section and the save path disagree.** AGENTS.md now says the right shape is a value that carries its engagement (`PostAction.saved(engagement)`) so a save without a journal line does not typecheck. No `PostAction` exists: `PostCard` calls `digests.save(...)` and then `imports.send(...)`, and the register row says "`digests.save` is the one save path" guarded by `DigestModelTests`. That test proves the model records every `Kind`; it cannot see a second view that calls `imports.send` without `save`. Either build the value — then the compiler is the guard — or write the row as the convention it is.

**A register row names a test that guards a different thing.** "`seen`/`hidden` were a second copy of the index" is fixed by computed properties, a type/shape fix at level 1. `testRecordingAMarkNotifiesTheReader` proves observation, not the absence of the copy. The row should say the compiler is the guard and the test the backstop, as the "one rule, one home" rule already requires.

**`reading.py`'s contract doc is false.** "Telegram reads public pages through `web` and takes no page" (`reading.py:5-7`), while `monitor` and `refresh` pass a page and `telegram.collect` uses it. The queue's "comments that lie" item closed three comments; this is a fourth, added by `5a2893b`.

**`syncState`'s comment is false.** "a second pull waits for this one" (`DigestModel.swift:24`) while `sync` returns at `:114`. Either await the running task — `LibraryModel.readJournals` already does — or say the second pull is dropped.

**The schedule guard proves less than the row implies.** `digest_script_checks` proves the plist has a `Minute`; it does not prove the hours match `BUILD_HOURS` (item 34). The row reads as if the whole schedule is guarded.

### Skill mismatches

Against `coding`:

- **Same race, two answers.** `LibraryModel.readJournals` awaits the read that is already running; `DigestModel.sync` drops the new one. The skill's stale-response rule asks for one defined behavior for overlapping work, and the repo now ships both.
- **One source of truth, one writer.** Item 35 (refresh writes the cache) and item 37 (the index held twice) are the two seam shapes the skill names as where bugs live.
- **Sameness parameterized.** Items 32, 33, 40 and 42 are one rule written twice with a literal changed, which the skill calls a defect rather than reuse.
- **What holds, and should not be touched.** Every wait is a named state (`DigestLoadState`, `DigestSyncState`, `CropPhase`, `EmbedPhase`); every task has an owner and cancels (`scoring`, `indexSave`, `progressWrite`); the sync loop is a real port with two adapters. These are the parts the branch got right.

Against `software-developer`:

- **"Report only what was checked."** The two register rows above claim a guard for a class the check cannot see. The work is right; the sentence is stronger than the proof.
- **"Surgical changes" and "restore only what is necessary".** `5a2893b` restored the repost label by copying the label chain into `ThreadScreen` instead of reusing `contextLabel`, which is how item 32 appeared.
- **"Start from the smallest thing that runs."** `DeliverySync` is the good case: two loops became one without changing either adapter's policy. `refresh` is the other case: it reached for `FileManager` inside the model instead of an operation on `DigestFile`.
- **Verification.** The branch runs `guards.py` (diff checks, source checks, whole server suite) and the new tests fail without their fixes, as the register says. The three skill paths in AGENTS.md exist and match the harness revision, so the mismatch is in what the rows claim, not in which skills are read.

### What I would do first

1. **`DigestFile` owns the refresh write** (items 35, 6): one actor writes the cache, one path rule covers packages and refreshed media.
2. **One sync behavior** (the `syncState` comment): await the running sync, as the library's journal read already does, or document the drop and make the pull say so.
3. **Move the source table and the schedule to one home** (items 33, 34): `reading.py` for the table and the browser rule, one constant consumed by both `build.py` and the plist writer.
4. **Reuse the card, the label and the stack** (items 32, 13, 14): one post card with variants, one `Context.Kind.label`, one generic stack.
5. **Share test support** (item 39): a small target both test bundles import, holding the tar writer, the post factory and the ISO encoder.
6. **Then the first pass's items 5, 6, 9, 10, 11, 12**, which none of the later commits touched.


# AGENTS.md (FNMN)

Rules for agents working in this repository.

- Project state: [notes/state/fnmn.md](notes/state/fnmn.md)
- Work queue: [notes/tasks.md](notes/tasks.md)
- Apple performance patterns compared with our code: [notes/state/performance.md](notes/state/performance.md)
- Task execution rules for structure and interfaces: [notes/plan.md](notes/plan.md). Use `architect` before changing structure and `coding` when implementing.

## Skills to load first

Before changing code, read these skills in full; they are not in the harness's skill catalog, so open the files:

- `~/.agents/skills/coding/software-developer/SKILL.md` — the working loop: smallest running step, every decision explained, verification before a checkpoint.
- `~/.agents/skills/coding/coding/SKILL.md` — the form of the code: one source of truth, ports at the boundary, tests at the seam, the code-shape rules.
- `~/.agents/skills/coding/design/architect/SKILL.md` — before a structural change: the call, the input, the result, the owner, and the variants.

If a skill and this file disagree, this file wins for this repository, and the PR says where they disagreed.

## Guard rule

Fixing a performance or correctness defect is not enough. **The same PR must add a check that keeps the defect from coming back, at the strongest level that can observe the whole class of the defect, not the line where it happened.** A fix without a guard is incomplete. These rules govern every new test, lint rule or check you add, whether it guards a bug, a regression found in review, or a rule the owner asked for.

Choose the level by what the check can see:

1. **Type or ownership** — when the bug was a state that should not exist, change the shape so it cannot be constructed (one enum instead of a flag that can disagree with a value). No check to add; the compiler is the guard.
2. **Unit test** (`App/FNMNTests`, `Tests/FNMNCoreTests`) — behavior of one class or function, including its errors and the order of its calls.
3. **Source test** (`ArchitectureGuardTests`, `ServerLinkGuardTests`, `HotPathGuardTests`) — an invariant across files or the whole app. It reads every file, not only the diff, so it also sees code that was already there.
4. **Lint rule** (`.swiftlint.yml`) — a call or a name in the source; runs before the build and in the editor.
5. **Diff check** (`scripts/guards.py`, `diff_violations`) — how new code is written: style, comments, language. It only sees added lines, so **it may never be the only guard for a behavior or an interaction**; the interaction is exactly what it cannot see.
6. **CI job** — build, toolchain, runner.

Then:

- **Prove the guard fails without the fix.** Revert the fix or plant the violation, watch the check fail, restore. The PR says which check was proven and how.
- **Generalize one step above the bug.** Do not guard the exact line or value that broke; guard the form that allowed it. "A view read a lazy value before it was loaded" becomes "every file that reads the value must trigger the load", not "this view calls this method".
- **One rule, one home.** If a rule is already guarded, extend that guard; do not add a second copy. A test and a lint rule may enforce the same rule only when one is the declared source of truth and the other a documented backstop.
- **Register it.** Add a row below with the level and how the guard was proven.

### One step above is a domain, not a neighbour

A check that names the value that broke is a second copy of the bug. Move up to the domain the value came from, and let the domain's size do the work.

- **Wrong:** a source check that greps `record(.saved` because one menu forgot to record a save. It knows that menu and nothing else, so the next menu that saves silently passes.
- **Right:** the finite parameter is exercised end to end. `DigestEngagement.Kind` is `CaseIterable`; one test sends every case through `DigestModel.record` and reads the journal back, and asserts one line per `Kind.allCases.count`. A new case fails until the writer handles it, and the test names no case.
- **Wrong:** a test that one view calls one method, or a grep for that method in that view. The interaction is exactly what a source read cannot see; the next view repeats the mistake.
- **Right:** one writer. The save is a value that carries its engagement (`PostAction.saved(engagement)`), and the only writer consumes it, so a save without a journal line does not typecheck. When one writer is not reachable yet, the next best check is the user path (a UI test on the button), never a diff check.

The question for every check: which values can reach this line, where do they come from, and does the check fail when a new one appears? "The function is called somewhere" is not coverage; a function with a finite parameter is covered only when every value of that parameter has gone through it.

## Code shape

- One implementation per query. Do not add a second overload that exists only to accept a cached list (for example `among:` with a fallback to the collecting path). Make the cache once, and let the query read it.
- Every block body is written on separate lines: function and computed-property bodies, initializers, `if`, `else`, `guard … else`, `for`, `while`, `switch` cases, and nested functions. Closures passed as arguments (`sorted { $0 < $1 }`, `map { … }`) may stay on one line when they are a single expression.
- Keep an expanded `if`/`else` expanded. Do not condense it back during a formatting pass.
- Write no comments in the code, neither `///` nor `//`. A name or a shape that needs a sentence beside it is the thing to change. `guards.py` refuses a comment on an added line.
- Do not reformat lines or files the change does not need to touch.

## Across the boundary

The server and the app model different things. To the server a page is `claude`, `chatgpt`, `substack` or a plain site, because each is parsed differently; to the app it is one article with a title and a text. Do not unify those classifications, their tables or their parsers across the process boundary, and do not share a host table between Swift and Python. The two sides agree on the wire format — `package.json`, the delivery archive, the file names — and on nothing else. A rule that exists only to keep two different models in step is a third model.

## Hot paths: how to keep them fast

- `LibraryQueries` (`Sources/FNMNCore/LibraryQueries.swift`) is the read side of the library. Building it walks and sorts the whole catalog, so only `LibraryModel` builds it, once per catalog change, in `refreshQueries()`.
- Screens read `library.queries`: `library.queries.items(matching:)`, `library.queries.albumSummaries`, `library.queries.groups(...)`, and so on. Every query is a filter or a sort over the stored arrays, not a rebuild.
- Do not write `LibraryQueries(` in `App/FNMN` outside `LibraryModel.swift`.

## Pipeline

Every change follows the same order. Each step leaves an artifact the next step and the owner can check.

| Step | What happens | Artifact |
|---|---|---|
| 1. Intake | One queue entry with the visible result and its acceptance check | `notes/tasks.md` |
| 2. Reproduce | A bug starts with a failing check; a feature starts with the acceptance check | test, source test, or measurement |
| 3. Design | Who owns the state, its shape, what contract changes; `architect` for anything structural | `APP_SPEC.md` in the same commit |
| 4. Implement | The smallest change in the existing forms | code and tests |
| 5. Guard | The strongest level above, proven to fail without the fix; generalize one step above the bug | test, lint or diff, plus the register row |
| 6. Verify | `python3 scripts/guards.py --app`; manual device checks for feel | green run |
| 7. Record | Commit story; PR with what/why/guard/proof/not-in; queue entry closed | PR and `notes/tasks.md` |

A bug never skips step 2, and a fix never skips step 5. When a step cannot be done, the PR says why in the same breath as the claim.

## Before opening a PR

Run from the repository root:

```sh
python3 scripts/guards.py --app   # diff checks, swiftlint --strict, lint self-test, swift test, FNMN app build and its unit tests
```

Without `--app` the build and the app unit tests are skipped. CI runs the same command with `--app` on each pull request.

## Guard register

Each defect below is closed by the check in the last column.

| Date | Defect | Guard |
|---|---|---|
| 2026-11-02 | Russian text in the agent rules, lint config, and PR description | `guards.py`: `cyrillic` on added lines |
| 2026-11-02 | One-line block bodies in new code, against the expanded style | `guards.py`: `one-line block` on added lines |
| 2026-11-02 | Doc comments added in long blocks (43 added comment lines in one PR) | `guards.py`: `comment`, any comment on an added line |
| 2026-11-02 | A second code path for cached lists (`among:` with a fallback), and duplicate overloads | `guards.py`: `among parameter` on added lines |
| 2026-11-02 | The Add to Collection sheet, search, and every screen rebuilt the whole catalog (~10–20 ms for 1,500 materials) in a view body; frames of the sheet's slide-in and of search typing were dropped | `snapshot_catalog_selector_in_view` in `.swiftlint.yml`; `HotPathGuardTests`; `guards.py` lint self-test, which must see the rule fire on a planted `LibraryQueries(` |
| 2026-11-02 | A change removed `@ViewBuilder` and `public` and broke the app build, while the PR claimed a build that was not run | `guards.py --app`: `xcodebuild` of the FNMN scheme on every PR |
| 2026-11-02 | Speed check compared two timings with no frame budget | `CollectedCatalogSpeedTests`: best of ten runs under 5 ms |
| 2026-11-02 | Tests read a `LibraryQueries` built before the library changed | `LibraryTests`: queries are rebuilt after each change |
| 2026-11-02 | CI ran Swift 6.3.3 while the package needs tools 6.4 | CI runner `xcode-27` |
| 2026-11-05 | The journal sync and import were moved out of `LibraryModel` with no behavior pinned first | `JournalTests`, `LibraryTests`, `JournalSyncTests` and `LibraryImporterTests`: the disk contract and the moved classes are pinned |
| 2026-11-05 | `LibraryModel` had grown back into the owner of journal and import disk work | `ArchitectureGuardTests`: `LibraryModel` may not call journal or import disk work |
| 2026-11-05 | Reading the Keychain inside `ServerLink.init`, which runs in `FNMNApp.init`, delayed the first frame | `ArchitectureGuardTests`: `ServerLink.init` has no `storage.load()`; `ServerLinkTests`: `init` does not touch the storage |
| 2026-11-05 | A view read `server.connection` before the lazy Keychain read had run, so a YouTube embed saw no server | `ServerLinkGuardTests`: a file that reads `server.connection` must call `savedConnection()` |
| 2026-11-07 | The digest tab could have brought a web view into a magazine that must draw with SwiftUI | `ArchitectureGuardTests`: a web view may appear only in `LiveCropView.swift` and `VideoReaderView.swift`, the whole app read; proven by planting an `import WebKit` in a digest card |
| 2026-11-07 | A digest could ship a post that opens nothing, or name a picture the delivery does not hold | `test_digest_build`: every post has a permalink and text or media, and every named file is in the tar; proven by skipping the media and by letting an empty post through |
| 2026-11-07 | A second build of the same posts would ship a duplicate digest, and a failed source would vanish from the magazine silently | `test_digest_build`: a rerun writes nothing, and a failed source rides in the package with its reason |
| 2026-11-07 | Engagement could be lost or raced: a detached task wrote the journal after the app already read it | `DigestModelTests`: settling writes each event to the device's journal once, and the journal decodes |
| 2026-11-07 | The server's tests never ran in CI, so server-side guards could not fail a pull request | `guards.py`: the server's whole test suite on every run; CI installs `server/requirements.txt` |
| 2026-11-08 | `digest/sources.py` shared its name with the server's root `sources.py`, so `from sources import …` inside the digest read the article link classifier and the parsers failed on an import error | `guards.py`: `source checks`, a module inside a server package may not be named like a module at the server root; self-test plants `server/digest/package.py` |
| 2026-11-08 | A commit swept the monitor's working store and a probe model into git, and a logged-in browser profile would have followed | `guards.py`: `source checks` refuses tracked files under `/out/`, `/profiles/`, `__pycache__`, `.build`, `.venv`; self-test tracks a planted `out/` file |
| 2026-11-08 | A digest of text-only posts could not be unpacked, and that one delivery then blocked every later one | `DigestTests`: a tar with only `package.json` is added; `DigestModelTests`: a text-only delivery is taken; proven by the same tar failing `moveItem` before the staging folder was created |
| 2026-11-08 | The launch sync read no index and wrote it back empty, so every post lost its read mark and every delivery was fetched again | `DigestModelTests`: a saved index and a fresh model keep `seen`/`hidden` through `sync`, and a purged cache is restored; proven by the probe that returned `seen: []` before the single `load` |
| 2026-11-08 | One unreadable delivery set the whole tab to failed and hid the deliveries that did read | `DigestModelTests`: a schema-2 tar beside a good one leaves the good magazine on screen and a `lastError` |
| 2026-11-08 | A package id or a newer schema could name a folder outside the digest or be read as an older one | `DigestTests`: empty, `.`, `..`, absolute and `\` are refused; a slash is written as a dash as before, and schema 2 is refused |
| 2026-11-08 | A hidden post left the sections but stayed in search | `DigestTests`: search takes the hidden set; `DigestModelTests`: the screen's query passes it |
| 2026-11-08 | Save to Library never wrote the `saved` engagement the training weights | `DigestModelTests`: every `Kind` case reaches the journal through `record`, and `DigestModel.save` is the one method the card calls; a second save site is a convention this test cannot see (AGENTS.md, "One step above") |
| 2026-11-08 | One picture with HTTP 403 threw out of the source and lost its whole batch | `test_digest_sources`: a Web that raises `HTTPStatusError` leaves the picture out and keeps the post; proven by the exception escaping `save_photo` before the `httpx.HTTPError` catch |
| 2026-11-08 | One post with neither text nor media stopped every later build | `test_digest_build`: the post is skipped with a reason, the next build runs, and a video without a poster is skipped; proven by two builds on one text-less post raising twice |
| 2026-11-08 | The build test read the machine's live subscriptions | `test_digest_build`: the build reads `--subscriptions` from a temporary file |
| 2026-11-08 | The login window launched Chrome with Playwright's `--no-sandbox`, and X's onboarding hung on the automation protocol | The login opens a plain Chrome process on the profile; `guards.py`: `browser sandbox` covers the headless reader that still uses Playwright; self-test plants a launch without `chromium_sandbox=True` |
| 2026-11-08 | The launchd builder set `Hour` without `Minute`, so it fired every minute of that hour | `guards.py`: `digest schedule` wants a `Minute` beside every `StartCalendarInterval` `Hour`, and the hours to come from `digest.build.BUILD_HOURS`; self-test plants an `Hour` alone and a script with fixed hours |
| 2026-11-08 | CI never reached the tests: the install step ran on the runner's Python 3.9, and `playwright`, `PyMuPDF`, `yt-dlp` and `yt-dlp-ejs` need 3.10 | CI job: `actions/setup-python` 3.12 before the install, the same version the `.venv` and the server tests are written against |
| 2026-11-08 | The library and the digest each had a file-name rule, and they disagreed on `a..b.jpg` | `PackagePathTests`: `..` and `.` refused, `a..b.jpg` kept; proven by the test failing before `PackagePath` existed, when the library refused that name |
| 2026-11-08 | The pdf-book tests passed locally and failed in CI: `ocr_jobs` imported `tqdm` when the module loaded, and the CI Python does not install it | `test_ocr_jobs` imports the module and runs the empty pass without the model's packages; `tqdm` is imported only when there are jobs |
| 2026-11-08 | Random bytes, names and sizes reached the digest reader | `DigestChaosTests` and `FuzzTests`: random tars, traversal names, a 200 KB file, a real package from the Mac, random image bytes and captions |
| 2026-11-08 | A source post without a time was stamped with `now`, so the magazine sorted it as the newest | `test_digest_sources`: a Telegram message and an Instagram page without a time are skipped; the source carries the count as its note |
| 2026-11-08 | A classifier that would not load looked exactly like a digest without one | `DigestModelTests.testABrokenClassifierIsReported`: a missing and a broken model both return an error, and the tab shows it |
| 2026-11-08 | A picture the store no longer held failed the whole build | `test_digest_build`: a missing picture is dropped and the text stays; a post left with nothing is skipped with `missing media` |
| 2026-11-08 | One folder of posts trained a one-class model, which labels every post with that folder | `test_digest_build.test_one_folder_is_not_enough_to_train`: twenty posts in one folder write no model |
| 2026-11-08 | The `_tweet` test handed a fake Web and never looked at the request | `test_digest_sources.test_the_syndication_request_names_the_status`: the URL names the status and the syndication endpoint |
| 2026-11-08 | `seen` and `hidden` were a second copy of the index, so a save could write the older one | The compiler is the guard: both read from `index`, so a copy cannot exist. `DigestModelTests.testRecordingAMarkNotifiesTheReader` proves a mark reaches an observer |
| 2026-11-08 | A refused picture had no state of its own, so the card lost the fact that a picture was expected | `test_digest_sources.PictureTests` asserts `media_errors`; `test_digest_build` keeps a post whose only media failed as a card, and `PostCard` draws the placeholder |
| 2026-11-08 | Media downloads used the article user agent instead of the logged-in page | `test_digest_sources.test_a_media_download_uses_the_page_context`: the page context serves the picture while the article Web refuses it |
| 2026-11-08 | A failed picture could only be recovered by waiting for a new digest | `test_digest_refresh` and `DigestModelTests.testARefreshBringsOnePicture`: one post is fetched again and its files land in the digest folder |
| 2026-11-08 | The library and the digest each listed, downloaded and imported deliveries in their own loop, so a fix in one missed the other | `DeliverySync`: one loop with `LibraryDeliveries` and `DigestDeliveries`; `LibraryImporterTests` and `DigestModelTests` exercise both adapters |
| 2026-11-08 | An import job could be given a card after it failed, and finishing closed a failed job | `ImportJobTests`: `Phase` carries the place, so the card lives in the state; proven by letting `placed` rewrite the phase, which attached a card to a failed job |
| 2026-11-08 | The name field lived in the view beside the dialog that owned the alert | `LibraryDialogsTests`: the draft travels in `LibraryDialog`; proven by building a fresh new-album dialog on each keystroke, which lost a rename |
| 2026-11-08 | A failed server check could not say whether the address and token were stored | `ConnectionCheckTests`: one transition maps a failed save and a failed check to the saved flag; proven by reporting a failed save as saved |
| 2026-11-08 | A deep link that arrived before the library could open it was a one-shot Bool on the view | `PendingRouteTests`: the route waits on `WindowNavigation` and opens once; proven by consuming it while the folder is still missing |
| 2026-11-08 | A background import request adopted after its end was completed as success | `ImportActivityTests`: one activity state over an `ImportActivityTask` port; proven by completing a late adoption as success |
| 2026-11-08 | A web page the app had replaced could write the new page's phase and take its resume | `WebGenerationTests`, `WebPageIdentityTests`: every page reports its generation and only the current one is heard; proven by accepting every number and by dropping it from the height message |
| 2026-11-08 | “Read” meant four things, so Continue hid a marked-read material while the continue deep link opened it | `ItemStatus` and `LibraryTests`: both Continue paths read one status; proven by removing the status check from `continuedID` |
| 2026-11-08 | A paused speed reader kept a clock, a stop was content rather than state, and a lifted finger left its state behind | `SpeedPlayerTests`, `PressTests`: one playback mode owns the clock and one press value owns the gesture; proven by letting `pause()` rewrite a stopped player |
| 2026-11-08 | A note synced from another device replaced the draft the person was typing | `NoteEditTests`: an open changed draft wins; proven by taking every arriving note into the draft |
| 2026-11-08 | A video played a file whose bytes the system had let go, and a seek outlived the page it was asked of | `VideoSourceTests`, `VideoStateTests`: the source is read from the disk and a failed page drops its seek; proven by keeping the seek on `.embed(.failed)` and on `.left` |
| 2026-11-08 | Comments narrated the state machines, the reader column and the post parts: prose beside names that already said it | `guards.py`: `comment` on added lines, proven by planting a `//` in `LoadState.swift` and watching the diff check fail |
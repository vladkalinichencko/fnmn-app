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

## Code shape

- One implementation per query. Do not add a second overload that exists only to accept a cached list (for example `among:` with a fallback to the collecting path). Make the cache once, and let the query read it.
- Every block body is written on separate lines: function and computed-property bodies, initializers, `if`, `else`, `guard … else`, `for`, `while`, `switch` cases, and nested functions. Closures passed as arguments (`sorted { $0 < $1 }`, `map { … }`) may stay on one line when they are a single expression.
- Keep an expanded `if`/`else` expanded. Do not condense it back during a formatting pass.
- Write comments in English, and only where the code cannot say why. A comment block is at most four lines.
- Do not reformat lines or files the change does not need to touch.

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
| 2026-11-02 | Doc comments added in long blocks (43 added comment lines in one PR) | `guards.py`: `comment block`, more than four lines in a row |
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

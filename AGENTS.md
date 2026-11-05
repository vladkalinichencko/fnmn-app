# AGENTS.md (FNMN)

Rules for agents working in this repository.

- Project state: [notes/state/fnmn.md](notes/state/fnmn.md)
- Work queue: [notes/tasks.md](notes/tasks.md)
- Apple performance patterns compared with our code: [notes/state/performance.md](notes/state/performance.md)
- Task execution rules for structure and interfaces: [notes/plan.md](notes/plan.md). Use `architect` before changing structure and `coding` when implementing.

## Guard rule

Fixing a performance or correctness defect is not enough. **The same PR must add a check that keeps the defect from coming back.** A fix without a guard is incomplete.

Guards live in one place: [scripts/guards.py](scripts/guards.py). CI runs it on every pull request and on `master`, and you run it before opening a PR. Do not copy a check into another file; add it to the script.

Guard types, from least to most strict:

1. **Diff check** (`scripts/guards.py`, `diff_violations`). Looks only at lines the change adds, so old code never fails it. Use it for a rule about how new code is written.
2. **Lint rule** (`.swiftlint.yml`, `custom_rules`). Catches the same violation in the source: before the build, in the editor, and in CI. Use it for a rule about a call or a name.
3. **Test guard** (`Tests/FNMNCoreTests`). Reproduces the wrong code shape or the expensive computation, and fails if it returns.
4. **Performance measurement** (`PerformanceTests` and `CollectedCatalogSpeedTests`). Budget: 5 ms for work that runs in a frame or on a keystroke, 100 ms for a single action.

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

## Before opening a PR

Run from the repository root:

```sh
python3 scripts/guards.py --app   # diff checks, swiftlint --strict, lint self-test, swift test, FNMN app build
```

Without `--app` the build is skipped. CI runs the same command with `--app` on each pull request.

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
| 2026-11-05 | The journal sync and import were moved out of `LibraryModel` with no behavior pinned first | `JournalTests` and `LibraryTests`: a saved sync and a kept link survive the disk round trip |
| 2026-11-05 | `LibraryModel` had grown back into the owner of journal and import disk work | `guards.py`: `disk work in LibraryModel` on added lines |
| 2026-11-05 | Reading the Keychain inside `ServerLink.init`, which runs in `FNMNApp.init`, delayed the first frame | `guards.py`: `storage read at launch` on an added `storage.load()` outside `savedConnection()` |

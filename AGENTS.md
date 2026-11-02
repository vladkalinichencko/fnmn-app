# AGENTS.md (FNMN)

Rules for agents working in this repository.

- Project state: [notes/state/fnmn.md](notes/state/fnmn.md)
- Work queue: [notes/tasks.md](notes/tasks.md)
- Apple performance patterns compared with our code: [notes/state/performance.md](notes/state/performance.md)
- Task execution rules for structure and interfaces: [notes/plan.md](notes/plan.md). Use `architect` before changing structure and `coding` when implementing.

## Guard rule

Fixing a performance or correctness defect is not enough. **The same PR must add a check that keeps the defect from coming back.** A fix without a guard is incomplete.

Guard types, from least to most strict:

1. **Test guard** (`Tests/FNMNCoreTests`). Reproduces the wrong code shape or the expensive computation, and fails if it returns.
2. **Lint rule** (`.swiftlint.yml`, `custom_rules`). Catches the same violation in the source: before the build, in the editor, and in CI.
3. **Performance measurement** (`PerformanceTests` and `CollectedCatalogSpeedTests`). Budget: 5 ms for work that runs in a frame or on a keystroke, 100 ms for a single action.

## Hot paths: how to keep them fast

- `LibraryQueries` (`Sources/FNMNCore/LibraryQueries.swift`) is the read side of the library. Building it walks and sorts the whole catalog, so only `LibraryModel` builds it, once per catalog change, in `refreshQueries()`.
- Screens read `library.queries`: `library.queries.items(matching:)`, `library.queries.albumSummaries`, `library.queries.groups(...)`, and so on. Every query is a filter or a sort over the stored arrays, not a rebuild.
- Do not write `LibraryQueries(` in `App/FNMN` outside `LibraryModel.swift`. The lint rule `snapshot_catalog_selector_in_view` and `HotPathGuardTests` catch it; both must stay green.

## Code shape

- One implementation per query. Do not add a second overload that exists only to accept a cached list (for example `among:` with a fallback to the collecting path). Make the cache once, and let the query read it.
- Every block body is written on separate lines: function and computed-property bodies, initializers, `if`, `else`, `guard … else`, `for`, `while`, `switch` cases, and nested functions. A one-line `{ expression }` block is not allowed in code a change adds or moves. Closures passed as arguments (`sorted { $0 < $1 }`, `map { … }`) may stay on one line when they are a single expression.
- Keep an expanded `if`/`else` expanded. Do not condense it back during a formatting pass.

## Before opening a PR

Run these from the repository root:

```sh
swift test          # tests, guards, and measurements
swiftlint --strict  # lint guards; the repository style rules are not part of this config
swiftformat --lint  # changed files only; do not reformat files you did not change
```

CI ([.github/workflows/tests.yml](.github/workflows/tests.yml)) runs `swift test` and `swiftlint --strict` on pull requests and on `master`.

## Guards written for found defects

| Date | Defect | Guard |
|---|---|---|
| 2026-11-02 | The Add to Collection sheet, search, and every screen rebuilt the whole catalog (~10–20 ms for 1,500 materials) in a view body. Frames of the sheet's slide-in and of search typing were dropped. | `HotPathGuardTests` and the `.swiftlint.yml` rule `snapshot_catalog_selector_in_view`; `CollectedCatalogSpeedTests` (album summaries over the built queries fit the 5 ms budget) |

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

- Do not collect the catalog in a view body. Screens read the material lists that `LibraryModel` keeps as observable properties and collects once per catalog change: `library.items(...)`, `library.albumSummaries()`, `library.groups(...)`, `library.groupName(...)`, `library.archivedItems`.
- Call the `snapshot.*` selectors that collect the catalog (`items(`, `albumSummaries`, `unsortedItems`, `continueItems`, `groups(`, `groupName(`, `archivedItems`, `annotationGroups`) only in `App/FNMN/Store/LibraryModel.swift`.
- `HotPathGuardTests` and the lint rule `snapshot_catalog_selector_in_view` catch violations of the rule above. Both must stay green.

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
| 2026-11-02 | The Add to Collection sheet, search, and every screen rebuilt the whole catalog (~10–20 ms for 1,500 materials) in a view body. Frames of the sheet's slide-in and of search typing were dropped. | `HotPathGuardTests` and the `.swiftlint.yml` rule `snapshot_catalog_selector_in_view`; `CatalogAlongsideTests` (selectors over collected materials return the same lists); `CollectedCatalogSpeedTests` (work over the collected catalog is much cheaper than collecting it) |

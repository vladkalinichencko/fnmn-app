# Implementation round: reader state and notes

## Visible result

FNMN can import prepared article or video JSON packages, add an article through the Mac service, read blocks and sections, restore the saved block or video time, and reopen and edit one note per block. Loading, importing and saving now show one coherent phase instead of contradictory spinners, sheets and errors. Direct PDF, DjVu and EPUB import, search, Share to FNMN and the learning feed remain outside this slice.

## Architecture

The current flow and module ownership are defined in [APP_SPEC.md](../APP_SPEC.md). `LibrarySnapshot` owns persisted packages, positions, folders and notes. `LibraryModel` changes that data and calls `LibraryFile` or `ArticleClient`. `LibraryView`, `AddArticleView`, `ReaderView` and `NoteEditor` keep their temporary interaction in explicit enums and reducers.

## Bugs found in the first layer

- `fnmn_service.py` emitted a MathML formula twice because the traversal accepted both its paragraph and the nested `<math>` node. Skipping descendants already owned by a paragraph fixed the package structure.
- A failed `state.json` write left optimistic in-memory changes behind. Each mutation now keeps the previous value and restores it when persistence throws.
- The note editor closed after a failed write because `save(note:)` could not return failure. It now throws, keeps the draft and closes only after success.
- Independent `showingNote`, `saving` and `errorMessage` values allowed impossible editor states. `NoteEditorState` now permits only editing, saving, failed or closed.
- Reader sheets were independent booleans, so outline and note presentation could conflict. `ReaderDestination` now permits one destination.
- Reusing `ReaderView` for another material could preserve the old block index and address a block outside the new package. The reader is now identified by `material.id`.
- Import fields could change while their request was starting. Submission now freezes the form and sends a captured request.

These are state-transition and ownership defects, so formatting and lint rules cannot detect them. The original coding guidance required FSMs but lacked a concrete Swift example and a product-facing reporting rule; both now live in the shared `coding` skill.

## Next implementation

Make “Continue” choose the most recently opened material and add explicit read/unread state through the existing snapshot and persistence path.

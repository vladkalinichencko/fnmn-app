# Implicit state machines

Line references in this note predate the 2026-11-08 folder move and the `LoadState` rename; the claims were checked again on 2026-11-08. Items 1, 3 and 11 are closed, and the nine that the owner took next (2, 4, 5, 6, 8, 10, 12, 13, 14) are closed on `unification`, each with a test that fails without it. Item 7 is left as it is, on purpose, and 9, 15 stay as they are.

Question: which state in the app is a machine that nobody named?

Scope: every Swift file under `App/FNMN` and `Sources/FNMNCore` (64 files, about 10,600 lines). I read every type that owns mutable state, every `@State`, `@AppStorage`, `@Observable`, task handle and static cache, and the tests only where they pin a transition.

A machine counts here when two or more fields together decide what the screen does, when the legal states are a product the type does not name, or when a transition lives in a view's `onChange`/`onAppear` instead of one `reduce`. A single enum with a complete reducer is explicit. I list such a reducer only where its fields still encode a second machine.

The reducers listed in [APP_SPEC.md](../../APP_SPEC.md#состояния-взаимодействия) are real. This note is what lives beside them.

## Ranked list

| # | Machine | Owner | Encoded as | What the missing state costs |
|---|---|---|---|---|
| 1 | Opening and jumping the column | `ReaderCoordinator` | `opening`, `hidesColumn`, `scrollID`, `place`, `keepsPlace` | A pending jump silently drops the reader's place; a column can stay hidden |
| 2 | Video source and pending seek | `VideoCoordinator`, `VideoReaderView` | `playable`, `originalFile`, `embed`, `seekTo`, `loaded`, `resumeAt` | Wrong player chosen after an iCloud eviction; a seek surviving a failure |
| 3 | Library readiness | `LibraryModel`, `WindowRoot` | `loadState` × `cloudFolder` × `failure` | `ready` that is not ready to show the library |
| 4 | Item status | `LibrarySnapshot` × `ReadingProgress` | `isRead`, `archived`, `positions`, `readThrough`, `lines`, `readings` | Four definitions of "read" that disagree |
| 5 | Import job | `ImportJobs` | `phase` × `itemID` × `running` | A task and its card kept in two places |
| 6 | Speed playback | `SpeedPlayer`, `SpeedReader` | `isPlaying`, `clock`, `token.isStop`, `furthest`; `holding`, `touchStart`, `holdTimer`, `playedBeforeHold` | A pause that keeps a clock; a stop that is content, not state |
| 7 | Plate aside | `PlateView` | `side: Bool?`, `drag`, `mode` | Gesture and reducer disagree for a frame, by design |
| 8 | Margin note editor | `MarginNote` | `draft`, `saved`, `active`, `focused` | A synced note overwrites an open draft |
| 9 | Progress write-behind | `LibraryModel`, `JournalSync` | `places`, `progressUnsaved`, `progressWrite`, `lastWrite`, `journalRead` | Position has two truths; single-flight is a task handle |
| 10 | Live Activity lifetime | `ImportActivity` | `step`, `backgroundID`, `background` | A request adopted after its end is completed as success |
| 11 | Connection check | `SettingsScreen` | `check` × saved `ServerConnection` | "Failed" can mean saved-but-unreachable |
| 12 | Deep link before load | `WindowRoot` | `pendingContinue` × `loadState` | One-shot latch, no timeout or cancel |
| 13 | Dialog draft | `LibraryDialogs` | `dialog` × `albumName` | The name field is outside the machine |
| 14 | Web content identity | `LiveCropView`, `YouTubeEmbedView` | `loaded`, `phase`, `shownHeights` | A late callback from the old page writes the new page's phase |
| 15 | Catalog migration | `LibraryFile` | `deletionsKnown`, file existence, `corruptPackageNames` | Format version is inferred from which files exist |

## 1. Opening and jumping the column

[ReaderState](../../App/FNMN/Reader/ReaderCoordinator.swift#L6-L29) is one struct with twelve fields. The reducer covers each action, but four fields form a machine of their own.

The machine: `opening != nil` means "a jump is pending; the column is hidden and its scroll position is not the reader's place". `hidesColumn` means "do not show the column until the jump lands". `scrollID` is where the column actually stands.

The transition is a two-phase commit across an async layout:

- `init` sets `opening` and `hidesColumn` together, and `hidesColumn = state.opening != nil` is the only place the two are tied ([L210-L219](../../App/FNMN/Reader/ReaderCoordinator.swift#L210-L219)).
- `.opened` clears `opening` and `hidesColumn` only when `opening` is set; otherwise it returns the state unchanged ([L68-L72](../../App/FNMN/Reader/ReaderCoordinator.swift#L68-L72)).
- `.scrolled` drops the person's scroll while `opening` is set ([L73-L75](../../App/FNMN/Reader/ReaderCoordinator.swift#L73-L75)).
- `.onePlate(false)` and `.speedRead` set `opening` again, without setting `hidesColumn` ([L120-L128](../../App/FNMN/Reader/ReaderCoordinator.swift#L120-L128), [L150-L164](../../App/FNMN/Reader/ReaderCoordinator.swift#L150-L164)).

So `opening` means two different things: the first open (hidden, scrollID not yet known) and a later jump (visible, rows already there). The type cannot say which. The legality rule "`hidesColumn` is true only while `opening` is the first jump" lives in the comments and in two call sites that send `.opened` after `Task.yield()` ([L409-L414](../../App/FNMN/Reader/ReaderCoordinator.swift#L409-L414), [L427-L432](../../App/FNMN/Reader/ReaderCoordinator.swift#L427-L432), and `ReadingSession`'s `.task` at [L131-L135](../../App/FNMN/Reader/ReadingSession.swift#L131-L135)).

What can go wrong: if `.opened` is never sent for a pending jump, `.scrolled` ignores every scroll, the place stops updating, and the column stays invisible when `hidesColumn` was set. There is no timeout, no cancel on `.left`, and no assertion that `.opened` arrives.

Shape: one enum, for example `column: .laidOut / .jumping(to: Int, hiding: Bool)`, with `.scrolled` switching on it instead of testing an optional. `place` stays a separate value, because it is reading data, not layout.

*Closed in 5533aec:* `ReaderState.column` is `laidOut` or `jumping(to:hiding:)`; `opening` and `hidesColumn` are computed from it, and `ReaderStateTests` covers a scroll before the jump, a second `.opened`, and a plate closing into a non-hiding jump.

## 2. Video source and pending seek

Two machines are stacked here.

**Source.** [VideoReaderView](../../App/FNMN/Video/VideoReaderView.swift#L127-L145) picks the player from `library.originalFile(materialID)` and a view-level `playable` URL ([L15](../../App/FNMN/Video/VideoReaderView.swift#L15)). `originalFile` is the listing of `originals/`; `CloudFolder.files` returns names for files that may still be only in iCloud, so a listed file is not necessarily on the device. The branch is:

```swift
if let file = originalFile, file != playable { download; playable = file }
else if let file = originalFile { SystemPlayer(url: file) }
else { YouTube embed }
```

`playable` is a cache of "this URL has been downloaded at least once". After iOS evicts the file, `originalFile` still returns the URL and `file == playable`, so the download branch is skipped and `AVPlayer` is handed a file that is not local. The source is genuinely derived (`originalFile`), but a second, non-invalidated copy of it decides the branch.

**Seek.** `VideoState.seekTo` is a command stored as state ([L23](../../App/FNMN/Video/VideoCoordinator.swift#L23)). It is set by `.jumped` and cleared only by `.seekDone` ([L65-L71](../../App/FNMN/Video/VideoCoordinator.swift#L65-L71)). `.embed(.failed)` and `.left` do not clear it. `YouTubeEmbedView` applies it only while `phase == .ready` ([L370-L380](../../App/FNMN/Video/VideoReaderView.swift#L370-L380)), so a seek requested during loading survives a failure and is applied later, out of context. `SystemPlayer` clears it immediately whether or not the seek succeeded ([L301-L309](../../App/FNMN/Video/VideoReaderView.swift#L301-L309)).

**Load identity.** `YouTubeEmbedView.Coordinator.loaded` and `resumeAt` ([L389-L400](../../App/FNMN/Video/VideoReaderView.swift#L389-L400)) are another optional-as-latch: `loaded` is the video ID whose page is in the web view, and `resumeAt` is a one-shot resume position consumed on the first ready update. Neither carries a generation, so a late message from the previous page is indistinguishable from the current one.

Shape: `enum Source { local(URL, ready: Bool), downloading(URL), embed(EmbedPhase) }` computed once, and `enum Seek { none, pending(Double), applied }`. The view then branches on one value.

*Closed in 6aa8223:* `VideoSource.of(original:downloading:onDevice:)` is read from the disk on every draw, so a file the system let go comes down again; `videoReduce` drops `seekTo` on `.embed(.failed)` and on `.left`, and `SystemPlayer` reports a seek done only when the system applied it. `VideoSourceTests` and `VideoStateTests` pin both; proven by keeping the seek on a failed page and on leaving.

## 3. Library readiness

[LibraryLoadState](../../App/FNMN/Store/LibraryModel.swift#L17-L23) names four states, and the app treats three more fields as part of the same state: `cloudFolder` ([L36](../../App/FNMN/Store/LibraryModel.swift#L36)), `failure` ([L42](../../App/FNMN/Store/LibraryModel.swift#L42)) and the journal read handle ([L52](../../App/FNMN/Store/LibraryModel.swift#L52)).

The screen state is the product:

| `loadState` | `cloudFolder` | What is shown |
|---|---|---|
| idle, loading | any | spinner |
| failed | any | "Library unavailable" + Try Again |
| ready | nil | folder picker |
| ready | URL | library |

`WindowRoot` encodes exactly this product as a four-arm switch ([L40-L55](../../App/FNMN/App/FNMNApp.swift#L40-L55)). `.ready` with no folder is a legal state of the enum that means "not ready". `failure` is an orthogonal banner that can sit on top of `ready` (a corrupt package, [L79-L83](../../App/FNMN/Store/LibraryModel.swift#L79-L83)) and on top of `failed`.

`load()` is guarded by the enum, so a second window waits instead of loading twice ([L66-L71](../../App/FNMN/Store/LibraryModel.swift#L66-L71)). But `syncWithOtherDevices()` runs after `ready` is published ([L75-L88](../../App/FNMN/Store/LibraryModel.swift#L75-L88)), so `ready` also does not mean "the other devices' changes are in".

Shape: `enum LibraryState { needsFolder, loading, ready, failed(String) }` with the folder as a case, or a computed `isUsable` that `WindowRoot` switches on. Keep `failure` separate: it is a message, not a state.

*Closed in 885d604:* `LibraryPhase` (`loading`, `needsFolder`, `ready`, `failed`) computed once from `loadState` and `cloudFolder`; `WindowRoot` switches on it, and a deep link waits for `ready` instead of firing on a folderless library.

## 4. Item status

The visible status of a material is a product of two stores:

- `LibrarySnapshot`: the entry exists, `archived`, `deletedAt` ([LibrarySnapshot.swift#L4-L15](../../Sources/FNMNCore/LibrarySnapshot.swift#L4-L15)).
- `ReadingProgress`: `readings[id].isRead`, `openedAt`, `progress`, `positions[id]`, `readThrough[id]`, `lines[id]`, `folded[id]` ([L6-L13](../../Sources/FNMNCore/ReadingProgress.swift#L6-L13)).

"Read" has four different definitions in the code:

1. `isRead` is a flag, set from the tile menu ([ItemTile.swift#L165-L168](../../App/FNMN/Library/ItemTile.swift#L165-L168)).
2. A paragraph is read from `isRead`, the read-through mark, the line's block, or scroll position, whichever applies ([ReadingProgress.swift#L70-L79](../../Sources/FNMNCore/ReadingProgress.swift#L70-L79)).
3. A block's share read is a line function ([L81-L86](../../Sources/FNMNCore/ReadingProgress.swift#L81-L86)).
4. "Started" for Continue is `openedAt != nil || positions != nil || readThrough != nil` ([ItemTile.swift#L171-L176](../../App/FNMN/Library/ItemTile.swift#L171-L176), [LibraryQueries.swift#L27-L36](../../Sources/FNMNCore/LibraryQueries.swift#L27-L36)).

Marking read also archives, and unmarking also unarchives, but only from the tile menu ([L167-L168](../../App/FNMN/Library/ItemTile.swift#L167-L168)); the archive menu toggles archive alone ([L182-L185](../../App/FNMN/Library/ItemTile.swift#L182-L185)). So `isRead == true, archived == false` and the reverse are both reachable, and "read" in the tile means something different from "read" in a paragraph.

Shape: keep the stores, add one derived `enum ItemStatus { unread, started, read, archived }` selector next to `continueItems`, and make every screen read it. This is the one place where deriving again is better than storing: the stores already merge by time across devices.

*Closed in 55e0681:* `ItemStatus` (`unread`, `started`, `read`) and `ReadingProgress.status(of:)`; the tile menu, Continue and the continue deep link read it, so a material marked read leaves both. `LibraryTests` pins the four answers and their agreement; proven by removing the status check from `continuedID`, which made the deep link open a read material again. Archiving stays a catalog fact beside the status, because marking read and archiving are two separate choices the person makes.

## 5. Import job

[ImportJob](../../App/FNMN/Store/ImportJobs.swift#L18-L38) has `phase` (`preparing(step)` or `failed(message)`) and an optional `itemID`. Completion is not a case; the job disappears ([L62-L90](../../App/FNMN/Store/ImportJobs.swift#L62-L90)). The four reachable states are:

| phase | itemID | On screen |
|---|---|---|
| preparing | nil | its own tile in Unsorted |
| preparing | id | the material's card, with a stage |
| failed | nil | its own tile with Try Again |
| failed | id | the card with Try Again |

`importReduce` guards `.progressed`, `.failed` and `.retry` by phase, but `.placed` is unguarded and may attach a card to a failed job ([L71-L72](../../App/FNMN/Store/ImportJobs.swift#L71-L72)). `.finished` removes a failed job as readily as a preparing one, and `.retry` keeps the card binding. The flow never produces a placed-after-failed today, so the invariant lives in the caller, not in the transition.

`running: [UUID: Task]` is a second copy of "which jobs are preparing" ([L96](../../App/FNMN/Store/ImportJobs.swift#L96), [L109-L115](../../App/FNMN/Store/ImportJobs.swift#L109-L115)). Tasks are started and cancelled by diffing the job list before and after the action. That works, but the reducer could produce a phase the dictionary has no task for, and the diff would not notice because it compares only `isPreparing`, not identity.

Shape: `phase` gains `done` only if the UI needs to show it; the real fix is to make `itemID` part of the phase (`onTile` / `onCard(id)`), and to store the task in the job itself or in a reducer-produced `effects` list.

*Closed in 3e88b27:* `ImportJob.Phase` carries `Place` (`tile` or `card(id)`), so a failed job cannot be given a card and `.finished` only closes a job still preparing; `itemID` is read from the phase. `ImportJobTests` drives `importReduce`; proven by letting `.placed` rewrite the phase, which attached a card to a failed job. The `running` dictionary stays: it maps a job to the task that runs it, and the list stays the only record of what exists.

## 6. Speed playback

[SpeedPlayer](../../App/FNMN/Reader/SpeedReader.swift#L30-L45) has `text`, `frame`, `isPlaying`, `furthest`, and a `clock` task. The visible modes are loading, paused, playing, stopped on a block, and at the end. None of them is stored as a state: loading is `text == nil`, paused is `!isPlaying`, and the other two are computed:

- a stop is `token?.isStop` (content, [SpeedText.swift](../../Sources/FNMNCore/SpeedText.swift#L21)),
- the end is `isAtEnd` ([L60-L63](../../App/FNMN/Reader/SpeedReader.swift#L60-L63)),
- `isPlaying` may be false while `clock` still holds the finished task ([L125-L140](../../App/FNMN/Reader/SpeedReader.swift#L125-L140)).

`play()` guards `isPlaying` and `token.isStop`, but nothing guards `isAtEnd`; at the end `token` is nil, so the guard fires by accident. `pause()` cancels and nils the clock; `run()` sets `isPlaying = false` on stop and end but does not nil the clock. The invariant "playing implies a live clock" holds today by call order, not by type.

The touch state is worse: `holding`, `touchStart`, `holdTimer` and `playedBeforeHold` ([L158-L161](../../App/FNMN/Reader/SpeedReader.swift#L158-L161)) are four fields for one machine — idle, pressed, holding, released — with cancellation spread across three closures ([L303-L331](../../App/FNMN/Reader/SpeedReader.swift#L303-L331)). `holding` true with no finger is representable; `playedBeforeHold` survives into the next gesture.

Shape: `enum Playback { loading, paused(frame: Range<Int>), playing, stopped(at: Int) }` owned by the player, with the clock started and cancelled by transitions into and out of `.playing`. The view gets `enum Press { idle, down(since: Date), holding(wasPlaying: Bool) }`.

*Closed in 0e5acbb:* `SpeedPlayback` (`loading`, `paused`, `playing`, `stopped`, `ended`) with `enter` as the one writer, so the clock lives exactly while the words run, and a stop survives a pause; `Press` (`idle`, `down`, `holding`) holds whether the words should start again. `SpeedPlayerTests` and `PressTests`; proven by letting `pause()` rewrite a stopped player, and by holding a press that already lifted.

## 7. Plate aside

[PlateView](../../App/FNMN/Reader/BlockView.swift#L176-L190) has three authorities for one position: `mode` (from the reducer), `side: Bool?` ("where the last swipe left the plate, until the mode catches up"), and `drag`. `open = side ?? noting` makes `Bool?` a tri-state: nil follows the mode, true is aside, false is closed.

The gesture commits by setting `side` and sending `.plate(.done)` or `.plate(.note(index))` in one animated block ([L265-L280](../../App/FNMN/Reader/BlockView.swift#L265-L280)). `onChange(of: noting) { side = nil }` is the reconciliation ([L220](../../App/FNMN/Reader/BlockView.swift#L220)). This is deliberate and the comment says why: a finger must move the plate from where it is on screen, not from where the reducer has got to. The illegal state (`side == true`, mode still `.reading`) is the point of the design, for the duration of one animation.

The cost is that a second input during that window has no defined meaning: `open` changes under a gesture that is still computing `offset` from the old value, and the mode that arrives is not the one the finger started with.

Shape: `enum Aside { closed, opening(translation: CGFloat), open, closing(translation: CGFloat) }`, with the committed direction as a case, not an optional beside the mode. This is a small machine; the current form is acceptable if tested at the seam.

## 8. Margin note editor

[MarginNote](../../App/FNMN/Reader/BlockView.swift#L366-L425) keeps `draft` (the text field), `saved` (the annotation), `active` (derived from `noting && drag == 0`), and `focused`. The save happens on two edges: `onChange(of: active)` when it turns false, and `onDisappear` when it is still true ([L414-L425](../../App/FNMN/Reader/BlockView.swift#L414-L425)). `onChange(of: saved) { draft = saved }` ([L414](../../App/FNMN/Reader/BlockView.swift#L414)) makes the store authoritative at all times.

That last line is the implicit transition that matters: a journal merge from another device, or a mark command that rewrites the annotation, replaces the open draft without asking. The editor has no dirty state and no conflict rule; "saved" wins by assignment.

`active` also falls to false the moment the finger moves the plate ([L204-L207](../../App/FNMN/Reader/BlockView.swift#L204-L207)), because the editor cannot draw over a moving plate. That ends editing on a drag, which is intended, but it means `active` is not "the person is editing"; it is "editing is allowed right now".

Shape: `enum NoteEdit { closed(saved: String), editing(draft: String), saving(draft: String) }`, with an explicit conflict rule (keep the local draft, or show both). The view then reads one value.

*Closed in c43a103:* `NoteEdit` holds `saved`, `draft` and whether the field is open; a note that arrives while a changed draft is open is ignored, and closing saves once. `NoteEditTests`; proven by letting every arriving note into the draft, which replaced what the person typed.

## 9. Progress write-behind

[LibraryModel](../../App/FNMN/Store/LibraryModel.swift#L111-L126) buffers saved places in `places`, publishes everything else at once, and schedules a write two seconds after the last change ([L203-L211](../../App/FNMN/Store/LibraryModel.swift#L203-L211)). Four fields form the machine: `places`, `progressUnsaved`, `progressWrite`, `lastWrite`; `journalRead` is a fifth single-flight latch ([L170-L180](../../App/FNMN/Store/LibraryModel.swift#L170-L180)).

States: clean, buffered (places non-empty), saving, failed-dirty. `position(of:)` reads `places` first and the published progress second ([L213-L219](../../App/FNMN/Store/LibraryModel.swift#L213-L219)), so the current place has two truths while a debounce is pending. The invariants ("places only holds `savePosition`", "any other change flushes places", "unsaved is true whenever places is non-empty") are enforced by three functions and stated in comments.

This one is well built: the flush order (apply places, record one journal event per material, write progress, write journal) survives a failed write, and the journal is the durable side. The finding is only that the state is unnamed, so a new `ProgressChange` case can break the `places` rule without a compile error.

Shape: an explicit `enum WriteState { clean, buffered([ProgressChange]), saving, failed }` inside the model, or at least a `private enum` for the buffer. Do not move it to `JournalSync`: the model owns the ordering.

## 10. Live Activity lifetime

[ImportActivity](../../App/Activity/ImportActivity.swift#L7-L27) is a global machine with three statics: `step`, `backgroundID`, `background`. `start` sets the step and asks for time, which sets the ID ([L30-L40](../../App/Activity/ImportActivity.swift#L30-L40)); `adopt` binds the task when the system calls back with a matching ID ([L43-L60](../../App/Activity/ImportActivity.swift#L43-L60)); `end` clears all three and completes the task if one is bound.

Reachable combinations the type allows: ID set with no task (requested, not yet adopted), task set with no ID (impossible only by convention), step nil with a task (cleared by `end` before the task completes). `end` before `adopt` is the interesting one: the late `adopt` sees a mismatch and completes the new task as success, not with the real status. A second `start` without `end` leaves the first request uncompleted until iOS expires it.

Shape: `enum Activity { idle, requested(id: String, step: ImportStep), running(task: BGContinuedProcessingTask, step: ImportStep) }`. The identifier check then becomes a switch, and `end` can complete whatever is bound.

*Closed in 9d49d03:* `ImportActivity.State` (`idle`, `requested`, `running`, `ended`) over a small `ImportActivityTask` port, so a test binds a fake task. A request the system adopts after the import ended completes with the import's own status. `ImportActivityTests`; proven by completing such a request as success.

## 11. Connection check

[ConnectionCheck](../../App/FNMN/Settings/SettingsScreen.swift#L3-L10) is a clean four-state enum, but the saved credential is a second machine beside it. `saveAndCheck` writes the connection to Keychain and memory before checking ([L85-L101](../../App/FNMN/Settings/SettingsScreen.swift#L85-L101)). A parse failure leaves `.failed` with nothing saved; a network failure leaves `.failed` with the new credential saved. One state name, two very different outcomes, and the user cannot tell which one they are in.

`onChange(of: address)` and `onChange(of: token)` reset to `.editing` ([L71-L72](../../App/FNMN/Settings/SettingsScreen.swift#L71-L72)), so the enum tracks the form, not the saved server. That is the right call, but it means `.connected` is also only "the last check passed", not "this form is saved and working".

Shape: `enum Check { editing, checking, connected, failed(message, saved: Bool) }`, or keep the credential out of the check state and show a separate "Saved" badge.

*Closed in 3e39946:* `ConnectionCheck.failed(String, saved: Bool)`; the screen says whether the address and token were written before the check failed.

## 12. Deep link before load

`WindowRoot` holds `pendingContinue` and consumes it when `loadState` becomes ready ([FNMNApp.swift#L71-L82](../../App/FNMN/App/FNMNApp.swift#L71-L82)). It is a one-shot latch with no owner: no timeout, no cancel when the URL is invalid, and no distinction between "waiting for the library" and "already handled". The same URL arriving twice sets it twice, harmlessly, but a URL arriving after `.ready where cloudFolder == nil` runs `continueReading()` immediately ([L80](../../App/FNMN/App/FNMNApp.swift#L80)) and mutates navigation under the folder screen.

Shape: `enum PendingRoute { none, waiting(Route) }` on `WindowNavigation`, consumed by the first screen that can show it.

*Closed in f1962af:* `PendingRoute` (`none`, `continueReading`) lives on `WindowNavigation` beside the tab and its stacks, and `showPending` opens it once the library is ready and asks for the route only then. `PendingRouteTests`; proven by consuming the route while the folder is still missing. The route itself is still computed at the moment it opens, since the place in the library may have moved while the app waited.

## 13. Dialog draft

[LibraryDialog](../../App/FNMN/Library/LibraryDialogs.swift#L6-L18) is a good explicit machine, and the one field it does not own is the draft: `albumName` is `@State` in the view modifier ([L67](../../App/FNMN/Library/LibraryDialogs.swift#L67)), shared by the create and rename alerts. The alert is presented from `dialogs.dialog.albumTarget`, a `String??` whose `.some(nil)` means "new album, standalone" ([L149-L151](../../App/FNMN/Library/LibraryDialogs.swift#L149-L151)). The double optional exists only because `presenting:` needs an optional payload; the case already carries the meaning.

The draft is cleared on create and cancel but not on `dismiss` ([L130-L143](../../App/FNMN/Library/LibraryDialogs.swift#L130-L143)). Today no path dismisses an alert without one of those buttons, so it is a latent inconsistency, not a live bug.

Shape: `case namingAlbum(adding: String?, draft: String)` and `case renamingAlbum(name: String, draft: String)`, so the draft travels with the state and no view needs to remember to clear it.

*Closed in 0d2d75f:* both cases carry the draft, `typeAlbumName` rewrites it, and the view binds the field to the dialog instead of its own `@State`. `LibraryDialogsTests`; proven by building a fresh new-album dialog on every keystroke, which lost a rename.

## 14. Web content identity

[LiveCropView](../../App/FNMN/Reader/LiveCropView.swift#L5-L18) has a correct `CropPhase` enum and a static `shownHeights` cache keyed by URL and selector. The cache is a second state store: `height` for `.loading` reads the last height of that figure from a previous instance ([L54-L58](../../App/FNMN/Reader/LiveCropView.swift#L54-L58)), which is deliberate (it avoids a layout jump). It is never cleared, and it is global across windows.

Both web views use `loaded` (a URL or video ID) as a hand-rolled generation ([LiveCropView.swift#L96-L110](../../App/FNMN/Reader/LiveCropView.swift#L96-L110), [VideoReaderView.swift#L389-L400](../../App/FNMN/Video/VideoReaderView.swift#L389-L400)). The delegate and script callbacks carry no identity, so a message from the page that was just replaced writes the new page's phase. `updateUIView` sets `phase = .loading` in a `Task` after the new load starts, which narrows the window but does not close it.

Shape: a `generation: Int` bumped on each load, passed to the coordinator with every callback, or a small `enum Content { none, loading(URL), shown(URL, CGFloat), failed(URL, String) }` where the URL is checked on arrival.

*Closed in 519f043:* `WebGeneration` in the core, carried into the page and sent back with every message; the page's own number is what the coordinator accepts, and a failure from a replaced navigation is dropped. The figure sends it from its injected script, the player from its page. `WebGenerationTests` and `WebPageIdentityTests`; proven by accepting every number and by dropping it from the height message.

## 15. Catalog migration

[LibraryFile.load()](../../Sources/FNMNCore/LibraryFile.swift#L139-L193) is a state machine over file formats: `state.json` present, else legacy fields; `articles.json` else `packages.json` else inline packages else a folder of packages; progress in `progress.json` else in `state.json`. The order of writes is the recovery rule (progress first, then the snapshot, then remove `packages.json`, and remove the legacy folder only when nothing was corrupt). `deletionsKnown` is a one-way flag read from `state.deletedAt != nil` and flipped after the journals fill in deletions ([L112-L114](../../Sources/FNMNCore/LibraryFile.swift#L112-L114), [L301-L310](../../Sources/FNMNCore/LibraryFile.swift#L301-L310)).

This is implicit but appropriate: it is a migration, it runs once, and the states are the shapes of the files on disk. Naming them would add a type that exists only during one launch. The only recommendation is to state the order as a list in the spec (it already is, [APP_SPEC.md](../../APP_SPEC.md#хранение)) and keep the "remove only when clean" rule tested.

## Smaller, real, and not worth a refactor on their own

| Where | Encoded as | Note |
|---|---|---|
| [ReadingSession](../../App/FNMN/Reader/ReadingSession.swift#L47-L49) | `width == 0`, `columnWidth == 0` | 0 is "not measured", not a width |
| [ShelfScreen](../../App/FNMN/Shelf/ShelfScreen.swift#L136-L138) | `width == 0` | Cards stay unseen until the first layout |
| [PlatePager](../../App/FNMN/Reader/PlatePager.swift#L18-L26) | `forward` | Remembers the direction of the last pull so the outgoing plate leaves the right way |
| [ReadingLineView](../../App/FNMN/Reader/ReadingLineView.swift#L44-L46) | `start: CGFloat?` | nil is "no finger on the pin" |
| [LibraryFile](../../Sources/FNMNCore/LibraryFile.swift#L105-L118) | `cloudFolder?`, `corruptPackageNames` | Folder access and a load warning are not one state |
| [ShareViewController](../../App/Share/ShareViewController.swift#L8-L20) | `didHandOff` | One-shot latch, correct |
| [ReaderAppearance](../../App/FNMN/Reader/ReaderSettings.swift#L243-L250) | `onePlateKey` array | "Read one plate at a time" is per material, stored as a set membership, not in `ReaderState` |

## What I did not count

- Pure layout values (`drag`, `size`, `noteHeight`, `stageHeight`, `quoteHeight`) that only move a view and are reset with it.
- Caches that never decide a branch (`ImageFiles.cache`, `LiveCropView.shownHeights` decides a height, so it is listed).
- `@AppStorage` preferences that are a setting, not a state: changing one is a user action, not a transition.
- The reducers as a whole. They are the explicit layer; this note is about the fields around them.

## Order of work, if this becomes a change

The guard rule in [AGENTS.md](../../AGENTS.md#guard-rule) applies to any of these. For machines 1, 2 and 4 the check is a unit test over the reducer with the illegal combination planted; for 3 and 11 a source test that the screen switch reads one value; for 5 and 10 a test that the task handle and the phase agree after every action.

1. Reader column handshake (1) and video source (2): the two with a wrong screen behind them.
2. Item status (4): the selector, then the screens.
3. Import job (5) and Live Activity (10): one lifecycle, two owners.
4. The rest as they are touched.

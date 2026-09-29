# FNMN: архитектура приложения

Этот файл описывает устройство кода iOS/iPadOS-приложения: модули, поток данных, состояния и то, где меняется каждое правило. Экраны и поведение описаны в [notes/design/library-ui.md](notes/design/library-ui.md); сначала меняется дизайн и этот файл, затем код. Сервис Mac описан в [mac/](mac/), учебная лента отложена в [SPEC.md](SPEC.md).

## Один цикл данных

```text
BOUNDARY ─────────→ STATE ──────────→ SELECTORS ─────→ VIEWS
LibraryFile          LibrarySnapshot    LibraryItem,      SwiftUI, только рисуют
MacServicePort       (данные)           AlbumSummary,     и шлют действия
Keychain             Coordinator.state  AnnotationGroup
                     (взаимодействие)        ▲
     ▲                    ▲                  │
     │                    └── reduce ◄── Action ◄── view
     └────────── effects (только из нового состояния) ──┘
```

Данные библиотеки живут в одном месте: `LibrarySnapshot`. Меняет их только чистая функция `LibrarySnapshot.applying(_: LibraryChange)`; `LibraryModel` применяет изменение, атомарно пишет результат на диск и публикует новый снимок. Всё, что экран показывает, но что не хранится как есть (плитки, Unsorted, альбомы с обложками, прочитанные абзацы, пункты меню выделения, группы полки), выводят селекторы FNMNCore. Взаимодействие экрана (открытый лист, выделение, свёртка, фаза плеера) живёт в координаторе этого экрана: одно `enum State`, одно `enum Action`, чистый `reduce`, эффекты запускаются только из нового состояния, их результат возвращается действием.

## Модули

| Модуль | Что содержит | От чего зависит |
|---|---|---|
| `FNMNCore` (Swift-пакет в корне) | Типы документа и библиотеки, `LibraryChange` и `applying`, селекторы, разбор Markdown на абзацы, выделения, свёртка, маршрут ссылки, файловое хранилище `LibraryFile`. Без SwiftUI и UIKit, покрыт тестами `swift test`. | Foundation |
| `FNMN` (приложение) | Хранилище `LibraryModel`, порт Mac, координаторы и вью. | FNMNCore, Textual |
| `Textual` (`Vendor/Textual`) | Отрисовка Markdown, формул (swiftui-math), кода с подсветкой Prism и таблиц в SwiftUI. Копия библиотеки Guille Gonzalez (MIT) с одной добавкой: `textualSelectionMenu` кладёт пункты приложения в меню выделенного текста. | SwiftUIMath, swift-concurrency-extras |
| `SwiftUIMath` (`Vendor/SwiftUIMath`) | Вёрстка формул. Копия swiftui-math (MIT) с одной добавкой: `\underbrace{…}` рисует скобку под основанием, как KaTeX. | — |
| `Share` | Передаёт ссылку в приложение через `CaptureHandoff`. | FNMNCore |
| `Activity` | Live Activity подготовки. | — |

Приложение подключает FNMNCore как локальный пакет, а не компилирует его файлы у себя: граница модуля становится проверяемой (`public` — это интерфейс), тесты и приложение собирают один и тот же код. Папка `App/FNMN` — синхронизируемая группа Xcode: новый файл попадает в сборку без правки проекта.

## Файлы приложения

```text
App/FNMN/
  App/        FNMNApp, AppShell (вкладки и поиск), WindowNavigation, Tokens (отступы, радиусы)
  Store/      LibraryModel (снимок, apply, импорт), ImportJobs (задачи Mac и Live Activity)
  Mac/        MacServicePort + ArticleClient, MacConnection + Keychain
  Library/    LibraryScreen, AlbumScreen, SourceScreen, ItemGrid, ItemTile, AlbumTile,
              AlbumPicker, AddMenu, LinkSheet, LibraryCoordinator
  Reader/     ItemScreen, MaterialReader (ArticleFlowView), BookReaderView, ReadingSession,
              BlockView, MarkedMarkdown, ReaderSettings, LiveCropView, ChatGPTHandoff
  Video/      VideoReaderView (встроенный YouTube, системный плеер, подписи)
  Shelf/      ShelfScreen, AnnotationList
  Search/     SearchScreen
  Settings/   SettingsScreen
  Intents/    ReadingIntents
```

| Было | Стало |
|---|---|
| `LibraryView` с `NavigationSplitView` и полем поиска | `LibraryScreen`: сетка Continue, Unsorted, Albums; поиск только во вкладке Search |
| `LibraryLists.swift`: строки списка, `FoldersView`, `FolderContents`, `BrowserSourcesView` | `ItemGrid`, `ItemTile`, `AlbumTile`, `AlbumScreen`, `SourceScreen` |
| `ShelfView.swift` с `AppShell`, `SearchView` и полкой | `AppShell`, `SearchScreen`, `ShelfScreen` в своих папках |
| `AddArticleView` с выбором папок и Mac-настройками | `AddMenu` + `LinkSheet`; подготовка в `ImportJobs`, плитка готовящегося материала в Unsorted |
| `MacConnectionView` | `SettingsScreen` |
| `LibraryModel.preparation` (одна подготовка с выбором папки) | `ImportJobs.jobs`: список задач со стадией, ошибкой и повтором |
| `folders`, `place`, `assign` | `albums`, `LibraryChange.addToAlbum / removeFromAlbum / createAlbum / renameAlbum / deleteAlbum` |
| `Highlight` с поиском цитаты по строке | `Annotation` с диапазоном в абзаце, слиянием пересечений и заметкой в той же записи |
| `packages` и `books` по отдельности в каждом экране | `LibraryItem` — одна проекция для плиток, поиска, источника и полки |
| Панель действий выделения внизу читателя | меню плашки, меню выделенного текста, панель инструментов режима Select Paragraphs |
| `ArticlePiece` с отдельными формулами и SwiftMath | `DocumentBlock`: граница — пустая строка; плашку рисует Textual, формула остаётся внутри абзаца |

## Данные

`LibrarySnapshot` — состояние библиотеки:

- `packages`, `books` — подготовленные статьи, видео и книги; `browserCatalog` — собранные ссылки и их источники.
- `albums` — имена альбомов по порядку; `placements[itemID]` — альбомы материала. Материал без альбома лежит в Unsorted.
- `positions[itemID]` — место чтения (`piece:<index>`) или секунда ролика (`videoSeconds`, точное `Double`); `readThrough[itemID]` — отметка «прочитано до сюда».
- `readings[itemID]` — время открытия, явная прочитанность, доля прочитанного.
- `annotations` — выделения и заметки; `archived` — архив; `addedAt[itemID]` — дата добавления; `videoFiles[itemID]` — скачанный ролик в `videos/`.

`LibraryChange` перечисляет все изменения этих данных: открыть, отметить прочитанным, архивировать, сохранить место, поставить «прочитано до сюда», создать, переименовать, удалить альбом, добавить в альбом и убрать из него, выделить, зачеркнуть, подписать и снять пометку, удалить материал. Новое изменение данных — новый случай этого перечисления и одна ветка `applying`.

Селекторы: `items` (неархивные материалы и ссылки каталога без пакета), `continueItems`, `unsortedItems`, `albumSummaries`, `items(inAlbum:)`, `items(matching:)`, `items(fromSource:)`, `archivedItems`, `annotationGroups`, `readPieces(of:current:)`, `annotationCommands(materialID:piece:span:)`.

## Состояния взаимодействия

Каждая машина — `enum State` и `enum Action` с чистым `reduce` рядом со своим координатором.

- **ImportJobs.** Задача: `preparing(stage, fraction)` → исчезает после сохранения или `failed(message)` → `retry` снова `preparing`, `dismiss` убирает. Держится на уровне приложения, поэтому переживает закрытие листа; Live Activity и фоновая задача iOS показывают первую идущую задачу.
- **LibraryCoordinator** (окно): `idle`, `addingLink(draft)`, `pickingFile`, `namingAlbum(draft)`, `renamingAlbum(name, draft)`, `pickingAlbum(itemID)`, `confirmingDelete(itemID)`, `confirmingAlbumDelete(name)`.
- **Settings:** `editing`, `checking`, `connected`, `failed(message)`.
- **Reader** (`ReadingSession`): режим плашки `PlateMode` — `reading | selectingText(piece) | selectingParagraphs(pieces) | noting(piece)`, свёртка `ReadingFold` и масштаб жеста pinch.
- **Video**: встроенный плеер `EmbedPhase` — `loading | ready | failed(message)`; источник выводится из данных: скачанный файл в `videoFiles`, идущее скачивание — задача `ImportJobs` с входом `videoFile`, иначе встроенный YouTube.

## Хранение

`LibraryFile` — единственный писатель на диск. Пользовательское состояние пишется в `state.json` атомарно после каждого изменения; пакеты статей — в `packages.json` и только при импорте или удалении, чтобы сохранение места чтения не переписывало всю библиотеку. Файлы статьи лежат ревизией в `articles/<id>/<revision>/`, книга — каталогом в `books/`. Старый `state.json` с `folders`, `highlights` и пакетами внутри читается и переписывается в новый вид при первой загрузке.

## Отрисовка документа

`ArticleBody.blocks` делит Markdown на блоки: заголовок, текстовая плашка, отдельная картинка, видео, живой кадр. Граница — пустая строка, кроме блоков кода и `$$…$$`. `BlockView` — единственное место, где тип блока выбирает вид. Плашку рисует Textual через `MarkedMarkdown`: он экранирует LaTeX внутри `$…$` и `$$…$$`, чтобы Markdown не съел `\,` и `_`, ставит выносную формулу на отдельную строку внутри абзаца, рисует `==текст==` и сохранённые выделения. Якорь выделения — цитата в тексте плашки после разбора.

## Инварианты

- Меняет данные только `applying`; вью и координаторы не трогают `LibrarySnapshot` напрямую.
- Производное не хранится: Unsorted, обложки, прочитанные абзацы и пункты меню считаются из снимка.
- Материал может лежать в нескольких альбомах; переименование альбома меняет его у всех материалов; удаление альбома возвращает его материалы в Unsorted, если других альбомов у них нет.
- Для одного абзаца и одного вида пометки пересекающиеся выделения сливаются в одну запись.
- Повторный импорт того же id заменяет пакет или книгу; если текст изменился, место и выделения этого материала сбрасываются.
- Результат асинхронной операции применяется только к задаче, которая его ждёт (`jobID`).
- Весь обмен с Mac идёт через `MacServicePort` поверх `MacConnection`.

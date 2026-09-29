# FNMN: архитектура приложения

Этот файл описывает устройство кода iOS/iPadOS-приложения: модули, поток данных, состояния и то, где меняется каждое правило. Экраны и поведение описаны в [notes/design/library-ui.md](notes/design/library-ui.md); сначала меняется дизайн и этот файл, затем код. Сервис Mac описан в [mac/](mac/), учебная лента отложена в [SPEC.md](SPEC.md).

## Один цикл данных

```text
BOUNDARY ─────────→ STATE ──────────→ SELECTORS ─────→ VIEWS
LibraryFile          LibraryCatalog     LibraryItem,      SwiftUI, только рисуют
MacServicePort       ReadingProgress    AlbumSummary,     и шлют действия
CloudFolderPort      (данные)           AnnotationGroup,
ImageFiles           Coordinator.state  ReaderDocument
Keychain             (взаимодействие)        ▲
     ▲                    ▲                  │
     │                    └── reduce ◄── Action ◄── view
     └────────── effects (только из нового состояния) ──┘
```

Данные библиотеки живут в двух хранилищах, потому что меняются с разной частотой. `LibraryCatalog` держит то, что меняется редко: записи материалов, книги, альбомы, заметки, архив. `ReadingProgress` держит то, что меняется при каждом абзаце: места чтения, «прочитано до сюда», время открытия и долю прочитанного. Каждое меняет только своя чистая функция: `LibraryCatalog.applying(_: CatalogChange)` и `ReadingProgress.applying(_: ProgressChange)`. `LibraryModel` применяет изменение каталога, атомарно пишет его на диск и публикует; `ProgressModel` применяет изменение прогресса в памяти и пишет свой файл после паузы. Правило на оба хранилища (новый текст сбрасывает место и выделения, удаление материала чистит оба) — это два изменения подряд из `LibraryModel`. Экран, который читает только прогресс одного материала, не просыпается от изменений каталога, и наоборот.

Всё, что экран показывает, но что не хранится как есть (плитки, Unsorted, альбомы с обложками, прочитанные абзацы, пункты меню выделения, группы полки), выводят селекторы FNMNCore из двух хранилищ. Селекторы читают готовые поля записей каталога и не разбирают тела статей. Взаимодействие экрана (открытый лист, выделение, свёртка, фаза плеера) живёт в координаторе этого экрана: одно `enum State`, одно `enum Action`, чистый `reduce`, эффекты запускаются только из нового состояния, их результат возвращается действием.

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
  Store/      LibraryModel (каталог, apply, импорт), ProgressModel (прогресс, запись с паузой),
              ImportJobs (задачи Mac и Live Activity), CloudFolderPort, ImageFiles (миниатюры)
  Mac/        MacServicePort + ArticleClient, MacConnection + Keychain
  Library/    LibraryScreen, AlbumScreen, SourceScreen, ItemGrid, ItemTile, AlbumTile,
              AlbumPicker, AddMenu, LinkSheet, LibraryCoordinator
  Reader/     ItemScreen, ReaderCoordinator, MaterialReader (ArticleFlowView), BookReaderView,
              ReadingSession, BlockView, MarkedMarkdown, ReaderSettings, LiveCropView, ChatGPTHandoff
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

`LibraryCatalog` — каталог:

- `articles` — записи подготовленных статей и видео (`ArticleEntry`): материал, источник, отрывок, путь обложки, заголовки разделов для поиска. Тела в записи нет. Отрывок, обложка и заголовки — содержимое материала, а не производное состояние: они считаются один раз при импорте или при переходе со старого формата.
- `books` — книги с оглавлениями; `browserCatalog` — собранные ссылки и их источники.
- `albums` — имена альбомов по порядку; `placements[itemID]` — альбомы материала. Материал без альбома лежит в Unsorted.
- `annotations` — выделения и заметки; `archived` — архив; `addedAt[itemID]` — дата добавления; `videoFiles[itemID]` — скачанный ролик в `videos/`.

`ReadingProgress` — прогресс:

- `positions[itemID]` — место чтения (`piece:<index>`) или секунда ролика (`videoSeconds`, точное `Double`); `readThrough[itemID]` — отметка «прочитано до сюда».
- `readings[itemID]` — время открытия, явная прочитанность, доля прочитанного.

`CatalogChange` перечисляет изменения каталога: архивировать, создать, переименовать, удалить альбом, добавить в альбом несколько материалов и убрать из него, выделить, зачеркнуть, подписать и снять пометку, удалить материал. `ProgressChange` перечисляет изменения прогресса: открыть, отметить прочитанным, сохранить место, поставить «прочитано до сюда», забыть материал. Новое изменение данных — новый случай одного из перечислений и одна ветка его `applying`.

Тело статьи читается из файла при открытии читателя и живёт, пока открыт читатель. `ReaderDocument` — то, что читатель получает готовым: блоки с простым текстом каждой плашки, заголовок-дубль, обложка, размеры разделов, источник. Его строит FNMNCore вне главного потока.

Селекторы: `items` (неархивные материалы и ссылки каталога без пакета), `continueItems`, `unsortedItems`, `albumSummaries`, `items(inAlbum:)`, `items(matching:)`, `items(fromSource:)`, `archivedItems`, `annotationGroups`, `readPieces(of:current:)`, `annotationCommands(materialID:piece:span:)`. Материал по id находится через словарь записей, а не перебором всех плиток.

## Состояния взаимодействия

Каждая машина — `enum State` и `enum Action` с чистым `reduce` рядом со своим координатором.

- **LibraryModel:** загрузка `idle`, `loading`, `ready`, `failed(message)`. Загрузку запускает модель один раз, сколько бы окон её ни ждало.
- **ImportJobs.** Задача: `preparing(stage, fraction)` → исчезает после сохранения или `failed(message)` → `retry` снова `preparing`, `dismiss` убирает и отменяет её опрос. Импорт папки FNMN проходит `downloadingFromCloud` и `importing(index, count)`. Держится на уровне приложения, поэтому переживает закрытие листа; Live Activity и фоновая задача iOS показывают первую идущую задачу и обновляются только при смене стадии или доли.
- **Search:** `idle`, `searching(requestID, query)`, `results(query, items)`. Ответ с чужим `requestID` отбрасывается, побеждает последний запрос.
- **LibraryCoordinator** (окно): `idle`, `addingLink(draft)`, `pickingFile`, `namingAlbum(draft)`, `renamingAlbum(name, draft)`, `pickingAlbum(itemID)`, `confirmingDelete(itemID)`, `confirmingAlbumDelete(name)`.
- **Settings:** `editing`, `checking`, `connected`, `failed(message)`.
- **ReaderCoordinator** (открытый материал): `opening`, `ready(ReaderDocument)`, `failed(message)`; внутри `ready` режим плашки `PlateMode` — `reading | selectingText(piece) | selectingParagraphs(pieces) | noting(piece)` и свёртка `ReadingFold`. Плашки получают координатор из окружения и шлют ему действия; замыканий во вью нет. Масштаб жеста pinch лежит в отдельном маленьком наблюдаемом значении, его читает только эффект свёртки.
- **Video**: встроенный плеер `EmbedPhase` — `loading | ready | failed(message)`; реплики транскрипта строятся один раз при открытии, наблюдаемое состояние — индекс активной реплики, а не секунда. Источник выводится из данных: скачанный файл в `videoFiles`, идущее скачивание — задача `ImportJobs` с входом `videoFile`, иначе встроенный YouTube.

## Хранение

`LibraryFile` — единственный писатель на диск, весь файловый ввод-вывод библиотеки, включая разбор выбранного файла или папки при импорте, идёт в нём, а не на главном потоке. Каталог пишется в `state.json` атомарно после каждого изменения; записи статей — в `packages.json` только при импорте или удалении. Прогресс пишется в `progress.json` через две секунды после последнего изменения, при уходе приложения в фон и при закрытии читателя. Тело и файлы статьи лежат ревизией в `articles/<id>/<revision>/`, книга — каталогом в `books/`. Старые `state.json` и `packages.json` с телами статей и прогрессом внутри читаются и переписываются в новый вид при первой загрузке.

Порты границы, по одному на внешний канал:

- `MacServicePort` — сервис Mac. Интервал опроса задания растёт от 1 до 5 секунд, пока стадия не меняется, и сбрасывается при смене.
- `CloudFolderPort` — папка FNMN в iCloud Drive: перечислить поставки, скачать одну, убрать её локальную копию (`evictUbiquitousItem`). Импорт идёт поставка за поставкой, поэтому на устройстве лежит одна поставка за раз.
- `ImageFiles` — картинки статьи с диска: размер без декодирования, миниатюра по размеру показа через ImageIO, кэш в памяти, который очищается при предупреждении о памяти. Вью не читают файлы картинок сами.

## Отрисовка документа

`ArticleBody.blocks` делит Markdown на блоки: заголовок, текстовая плашка, отдельная картинка, видео, живой кадр. Граница — пустая строка, кроме блоков кода и `$$…$$`. `BlockView` — единственное место, где тип блока выбирает вид. Плашку рисует Textual через `MarkedMarkdown`: он экранирует LaTeX внутри `$…$` и `$$…$$`, чтобы Markdown не съел `\,` и `_`, ставит выносную формулу на отдельную строку внутри абзаца, рисует `==текст==` и сохранённые выделения. Якорь выделения — цитата в тексте плашки после разбора.

## Инварианты

- Меняет данные только `applying` своего хранилища; вью и координаторы не трогают `LibraryCatalog` и `ReadingProgress` напрямую.
- Производное состояние не хранится: Unsorted, альбомы с обложками, прочитанные абзацы и пункты меню считаются из хранилищ. Отрывок, обложка и заголовки статьи — её содержимое, они хранятся в записи каталога.
- В `body` вью нет разбора Markdown, чтения файлов и сборки всех плиток: это делают селекторы по готовым полям или координатор при открытии.
- Материал может лежать в нескольких альбомах; переименование альбома меняет его у всех материалов; удаление альбома возвращает его материалы в Unsorted, если других альбомов у них нет.
- Для одного абзаца и одного вида пометки пересекающиеся выделения сливаются в одну запись.
- Повторный импорт того же id заменяет пакет или книгу; если текст изменился, место и выделения этого материала сбрасываются.
- Результат асинхронной операции применяется только к задаче, которая его ждёт (`jobID`).
- Весь обмен с Mac идёт через `MacServicePort` поверх `MacConnection`.

# Apple: паттерны скорости, памяти и диска

Вопрос: какие приёмы из 17 статей Apple о производительности стоит держать в коде FNMN. Что из этого нарушено сейчас, записано в [state/performance.md](../state/performance.md).

Первые пять статей (отзывчивость, SwiftUI, зависания, ранняя диагностика, запуск) сводятся к одному правилу. Главный поток только рисует и обрабатывает ввод. Всё остальное считается заранее в другом месте и кладётся в кэш, а view читает готовый результат. Остальные статьи применяют то же правило к памяти, диску и энергии.

## Главный поток и зависания

Пороги. Задержка ответа на нажатие свыше 100 мс заметна, и у приложения из неё меньше половины. Кадр занимает 8,3 мс на 120 Гц и 16,7 мс на 60 Гц, а работа главного потока на кадр должна укладываться примерно в 5 мс. Инструменты Apple называют зависанием занятый run loop от 250 мс.

- `Task { синхроннаяРабота() }` внутри view наследует `MainActor`, поэтому зависание только откладывается. Тяжёлую работу выносят в `async nonisolated` функцию или, если она синхронная, в `Task.detached`. У detached-задачи приоритет по умолчанию `.medium`, его выбирают явно.
- Работу, которой не нужен главный поток, туда не отправляют даже через `await` на `MainActor`, потому что она придёт посреди жеста и даст рывок.
- Главный поток не ждёт фоновый: `DispatchSemaphore.wait` и `group.wait` блокируют его и вызывают инверсию приоритетов. Если ожидание неизбежно, QoS ждущего потока не выше QoS сигналящего.
- Синхронный ввод-вывод, чтение файлов и сеть на главном потоке запрещены. Файлы читают на отдельной очереди или актором, результат возвращают на главный поток.
- Свои потоки не создают. Swift concurrency, Dispatch и `OperationQueue` держат пул под число ядер, а лишние потоки делают каждый поток, включая главный, реже запущенным.
- Обновление экрана делят на подготовку данных (в фоне) и применение (на главном потоке), а пользователю показывают, что подготовка идёт.
- Проверки: XCTest `measure {}` с базой 100 мс для дискретных действий и 5 мс для кода, который работает во время непрерывного жеста; `XCTOSSignpostMetric` считает hitches. Thread Performance Checker включён в Run по умолчанию. Hang Detection на устройстве включается в Settings › Developer. Animation Hitches проверяют на реальном устройстве, лучше на самом старом из поддерживаемых.

## SwiftUI: тело view и частота обновлений

- `body` вычисляется часто. В `body`, в `init` view, в `onAppear`, `onChanged` и других модификаторах не делают долгой работы: считают асинхронно и кэшируют результат.
- Долгие обновления и частые обновления лечатся по-разному. Долгие ищут в дорожке View Body Updates вместе с Time Profiler. Частые ищут в Update Groups и в графе причин Show Causes: синие узлы это код приложения, серые это система.
- Объект с несколькими наблюдаемыми свойствами будит view при изменении чужого свойства. `@Observable` отслеживает только прочитанные свойства, но гранулярность у него на уровне свойства: одно свойство-структура будит всех, кто прочитал любую её часть.
- `GeometryReader` и `ScrollViewReader` пересчитывают раскладку при изменении родителя. View с состоянием, не влияющим на раскладку, выносят в отдельную иерархию. В `onGeometryChange` сначала сравнивают величину изменения с порогом.
- Замыкания в полях view захватывают состояние родителя, и SwiftUI пересчитывает их результат при любом его изменении. Билдер-замыкание вызывают в `init` и хранят результат, `@escaping` не ставят. Замыкания действий (`Button`) и замыкания с параметром (`ForEach`) можно не трогать.
- Сначала уменьшают самый частый источник обновлений, потом остальные.

## Отрисовка

- Flash Updated Regions показывает области, которые перерисовываются без видимых изменений.
- Несколько эффектов Liquid Glass объединяют в `GlassEffectContainer`, но не группируют далёкие друг от друга view: изменение посередине заставит обновиться обе группы. Области рядом со стеклом обходятся дороже.
- Простой фон дешевле сложных эффектов. Анимации делают короткими и останавливают по завершении. Тёмные пиксели потребляют меньше энергии.
- Видео играют через `AVPlayer`.

## Память и терминации

- Картинки приводят к размеру показа. Внешние и большие декодируют через ImageIO с уменьшением, а не целиком.
- Память, которую приложение держит и не использует, утечки не показывают. Пример Apple: словарь загруженных сообщений растёт без границы. Ненужное отбрасывают или пишут на диск.
- Ресурсы view освобождают при уходе в фон. Циклы владения ищут в Leaks и Memory Graph.
- Core Data держит несохранённые изменения в памяти: чем реже сохранение, тем больше память, чем чаще, тем больше запись на диск.
- При предупреждении о нехватке памяти реагируют быстро и не обходят весь граф объектов, потому что сжатые страницы вернутся в RAM. Большие выделения делают постепенно, чтобы система успела освободить память. `NSPurgeableData` не сочетают с `NSCache`.
- Причины терминации: abort, лимит памяти, bad access, watchdog запуска, memory pressure в фоне, таймаут фоновой задачи, блокировка файла в App Group. Memory pressure не убрать совсем, поэтому нужно восстановление состояния и малая память в момент suspend.
- Регрессии памяти ловит `XCTMemoryMetric` в `measure(metrics:)`.

## Диск и резервная копия

- Запись на SSD идёт блоками по 4 КБ, поэтому байт изменений пишет 4 КБ. Создание или удаление файла пишет 8 КБ метаданных, переименование до 16 КБ. Система присылает исключение при превышении суточного порога записи (Organizer, MetricKit).
- Мелкие изменения собирают и пишут одной записью. Цикл открыть, записать, закрыть один и тот же файл увеличивает число записей, а цена пакетирования это память.
- JSON и plist переписываются целиком. Данные, которые меняются часто, хранят отдельно от редко меняющихся. Для часто меняющихся документов Apple рекомендует SQLite, SwiftData или Core Data.
- Атомарная запись добавляет временный файл, отвязку и переименование, её используют только когда нужна. `fsync` и `F_FULLFSYNC` не вызывают, для барьера хватает `F_BARRIERFSYNC`.
- SQLite: не закрывать соединения без нужды, писать транзакциями, ставить индексы (`EXPLAIN QUERY PLAN`), включить WAL, не вызывать `VACUUM`.
- Регрессии записи ловит `XCTStorageMetric`.
- Восстановимое кладут в `Caches` или `tmp`: система чистит эти каталоги, iCloud Backup их пропускает. Невосстановимое и тяжёлое, которое можно скачать заново (фильмы, но не импортированные пользователем PDF), помечают `isExcludedFromBackup` на каталоге. Флаг сбрасывается некоторыми файловыми операциями и ставится после каждого пересохранения. `Caches` для исключения невосстановимых данных не используют. Каталог внутри `Library` называют по bundle id.
- `copyItem` на APFS создаёт клон и не удваивает место. `evictUbiquitousItem` убирает локальную копию файла iCloud.

## Запуск

- Запуск измеряется до первого кадра. Холодный запуск после тяжёлой игры или перезагрузки заметно медленнее тёплого, поэтому проверяют оба.
- Каждая сторонняя динамическая библиотека добавляет время запуска. Статические инициализаторы (`+load`, `__attribute__((constructor))`, C++) выполняются до `main()`.
- В `didFinishLaunching` делают только нужное для первого экрана. Синхронизацию с сетью откладывают, хранилище и геолокацию инициализируют при первом использовании, для первого экрана читают только нужные данные, а плитки рисуют заглушками.
- Работа после первого кадра в метрику не входит, но пользователь её ждёт. Её размечают `os_signpost` в категории `pointsOfInterest`.
- Инструменты: шаблон App Launch, панель Launch Time в Organizer (p50 и p90), MetricKit.

## CPU, сеть, размер

- CPU: подходящий алгоритм, кэш вычисленного, переиспользование объектов, события вместо опроса, системные фреймворки. Независимая операция должна занимать 10 до 100 мс, QoS берут самый низкий из подходящих.
- Сеть: один экземпляр `URLSession`, `waitsForConnectivity`, для необязательных запросов `allowsExpensiveNetworkAccess = false` и `allowsConstrainedNetworkAccess = false`. Запросы собирают и сжимают. Крупные загрузки идут через `background(withIdentifier:)`, необязательные с `isDiscretionary`.
- Фоновые задачи: `earliestBeginDate` с экспоненциальной паузой между повторами, быстрый `setTaskCompleted(success:)`, обработка `expirationHandler`. Задача, которая не уложилась в срок, завершает приложение с причиной Task Timeout.
- Размер: каталоги ассетов, удаление неиспользуемых файлов, данные в plist, а не в коде, HEIF и HEVC, 8-битные PNG. Не менять файлы между версиями без нужды: обновление считается по разнице.

## Источники

Статьи Apple, все из списка пользователя:

- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Understanding hangs in your app](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app)
- [Diagnosing performance issues early](https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early)
- [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)
- [Reduce terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app)
- [Making changes to reduce memory use](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)
- [Preventing memory-use regressions](https://developer.apple.com/documentation/xcode/preventing-memory-use-regressions)
- [Responding to low-memory warnings](https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings)
- [Basic size optimization](https://developer.apple.com/documentation/xcode/doing-basic-optimization-to-reduce-your-app-s-size)
- [Advanced size optimization](https://developer.apple.com/documentation/xcode/doing-advanced-optimization-to-further-reduce-your-app-s-size)
- [Scheduling CPU work efficiently](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently)
- [Improving rendering efficiency](https://developer.apple.com/documentation/xcode/improving-your-app-s-rendering-efficiency)
- [Reducing networking and Bluetooth power usage](https://developer.apple.com/documentation/xcode/reducing-networking-and-bluetooth-power-usage)
- [Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [Reducing your app's disk usage](https://developer.apple.com/documentation/xcode/reducing-your-app-s-disk-usage)
- [Optimizing your app's data for iCloud Backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)

# AGENTS.md (FNMN)

Правила для агентов, работающих в этом репозитории. Живое состояние проекта: [notes/state/fnmn.md](notes/state/fnmn.md); очередь работ: [notes/tasks.md](notes/tasks.md); паттерны Apple против нашего кода: [notes/state/performance.md](notes/state/performance.md); правила исполнения задач на структуру и интерфейсы — `architect` перед изменением структуры и `coding` при реализации ([notes/plan.md](notes/plan.md)).

## Правило ограждений

Каждый найденный дефект производительности или правильности закрывается не только правкой кода: **в том же PR появляется проверка, чтобы дефект не вернулся**. Правка без ограждения считается незаконченной. Формы по возрастанию строгости:

1. **Тест-ограждение** (`Tests/FNMNCoreTests`) — воспроизводит неправильную форму кода или дорогое вычисление и падает на её возврате.
2. **Линт-правило** (`.swiftlint.yml`, раздел `custom_rules`) — то же нарушение в форме исходника: ловит его до сборки, в редакторе и в CI.
3. **Измерение производительности** (`PerformanceTests`, а также `CollectedCatalogSpeedTests`) — бюджет «5 мс для работы, которую запускает кадр или клавиша, 100 мс для отдельного действия».

## Горячие пути: как их не возвращать

- Экраны не собирают каталог в теле view. Списки материалов — готовые наблюдаемые списки `LibraryModel`, собираемые один раз на изменение каталога: `library.items(...)`, `library.albumSummaries()`, `library.groups(...)`, `library.groupName(...)`, `library.archivedItems`. Прямые вызовы селекторов `snapshot.*`, которые собирают каталог заново (`items(`/`albumSummaries`/`unsortedItems`/`continueItems`/`groups(`/`groupName(`/`archivedItems`/`annotationGroups`), разрешены только в `App/FNMN/Store/LibraryModel.swift`.
- Нарушение первого пункта ловят тест `HotPathGuardTests` и линт-правило `snapshot_catalog_selector_in_view` — оба обязаны оставаться зелёными.

## Перед PR

Из корня репозитория:

```sh
swift test          # тесты, ограждения и измерения
swiftlint --strict  # линт-ограждения (стиль репозитория в конфиг не входит)
swiftformat --lint  # на изменённых файлах; нельзя массово форматировать чужие
```

CI ([.github/workflows/tests.yml](.github/workflows/tests.yml)) гоняет `swift test` и `swiftlint --strict` на PR и `master`.

## Ограждения, написанные на найденные дефекты

| Дата | Дефект | Ограждение |
|---|---|---|
| 2026-11-02 | Листик «в коллекцию», поиск и каждый экран пересобирали весь каталог (~10–20 мс на 1500 материалов) в теле view; кадры выезда листика и ввода поиска пропадали | `HotPathGuardTests` + `.swiftlint.yml` `snapshot_catalog_selector_in_view`; `CatalogAlongsideTests` (селекторы с собранными материалами отвечают теми же списками); `CollectedCatalogSpeedTests` (путь по собранному каталогу в разы дешевле сборки) |

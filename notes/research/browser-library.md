# Browser library export

[`browser_library.py`](../../mac/collect/browser_library.py) собирает Safari Reading List, выбранные Safari Tab Groups и папки Dia в [`browser-library.json`](../../browser-library.json). Результат хранит один объект на конкретный источник, его существующую страницу-каталог, материалы и итоговые категории в `saved_in`. Поле `found_in` сохраняет реальные места исходных ссылок, включая конкретную Safari-группу. Сохранённый каталог без отдельных материалов остаётся источником с пустым `materials`. Если несколько закладок ведут на один материал через разные URL, `saved_urls` сохраняет каждый исходный адрес.

Источники определяются по устойчивой структуре URL. Substack связывается с каталогом публикации, Medium и X с автором, GitHub с репозиторием, MIT OpenCourseWare с курсом, Habr с компанией или автором. Сохранённые YouTube-плейлисты и видео со ссылкой на плейлист раскрываются через `yt-dlp`; отдельное видео без тематического плейлиста связывается с каналом. Подтверждённые каталоги персональных блогов, корпоративных разделов, изданий, курсов, проектов и документов записаны в [`browser_source_overrides.json`](../../mac/collect/browser_source_overrides.json). Ошибки следующего запуска остаются в `review`.

К Safari добавлены четыре актуальные группы из `SafariTabs.db`: 47 URL из `best render engines learning content`, 32 из `Self-studу`, 22 из `research blog posts` и 5 из `UI History`. Пустые Start Page и служебные узлы Safari не экспортируются. Render Engines и Self Study распределяются по Theory Sources и Theory Videos по типу URL, Research Blog Posts входит в Theory Sources, UI History — в UX/UI. Дедупликация выполняется вместе с Reading List и Dia, а не отдельно для каждой группы.

Текущий экспорт охватывает 489 исходных записей и 476 уникальных URL. После объединения повторов и раскрытия плейлистов в нём 344 источника и 937 вложенных материалов; 68 сохранённых страниц сами являются источниками. В `review` и `errors` нет записей.

Tab Groups Dia не входят в результат. [`dia-local-sources.md`](dia-local-sources.md) фиксирует, что их локальные базы не читаются как SQLite или JSON. Для добавления групп нужен экспорт URL из интерфейса Dia или отдельный доступ к живому внутреннему API.

## Подготовка для локального импорта

Команда ниже создаёт `prepared-browser-library/catalog.json` с исходной иерархией и по одному пакету в `deliveries/` для каждого подготовленного материала. Повторный запуск пропускает готовые пакеты. Видео можно сначала сохранить без подписей для проверки плеера, затем дополнить их через yt-dlp.

```sh
.venv/bin/python mac/prepare_browser_library.py browser-library.json prepared-browser-library --seed-videos
.venv/bin/python mac/prepare_browser_library.py browser-library.json prepared-browser-library --kind web --workers 2
.venv/bin/python mac/prepare_browser_library.py browser-library.json prepared-browser-library --kind video --enrich-videos --workers 1
```

В приложении выберите папку `prepared-browser-library` через **Add → Choose library or book folder**. FNMN сохранит каталог и готовые статьи и видео в локальной библиотеке. Ссылки без готового пакета остаются в **Sources** и открывают исходную страницу. Для короткой проверки используйте `prepared-browser-library/smoke/FNMN-Test-Import.zip`: распакуйте архив в Files и выберите папку `FNMN-Test-Import`.

Пакет от 28 сентября содержит 344 источника и 899 готовых материалов: 329 веб-страниц и 570 видео. У 28 видео есть подписи; остальные видео открываются без транскрипта. 33 веб-ссылки остаются ссылками на оригинал: интерактивная проверка Cloudflare (ACM), отказ по IP выхода VPN (Хабр и ещё три сайта), пейвол NYT и WSJ, удалённые страницы, сетевые сбои с этого Mac, голые PDF, ноутбуки Jupyter, X Articles за логином и ссылка на YouTube-канал. В приложении они лежат плитками-ссылками в своих альбомах из `index.json`. Поставки — tar в `prepared-browser-library/deliveries`, телефон берёт их из папки FNMN в iCloud Drive, которую собирает `mac/publish_library.py`.

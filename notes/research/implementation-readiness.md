# Implementation readiness

Проверено 20 сентября 2026 года для согласованного MVP: статьи сначала, iOS/iPadOS 27, SwiftUI с системными контролами, скрипты на Mac и REST-сервис. Продуктовый код здесь не менялся.

## Локальная среда

На машине установлены Xcode 27.0 (build 27A266a), Swift 6.4 (`swift-driver 1.168.6`), iOS 27.0 и iOS Simulator 27.0 SDK. `xcodebuild -version`, `xcodebuild -showsdks`, `xcrun --find swift` и `swift --version` прошли; предупреждение Xcode о `DVTFilePathFSEvents` не помешало выводу SDK. В каталоге пока нет Xcode-проекта и Git-репозитория: [state/fnmn.md](../state/fnmn.md) подтверждает, что код приложения ещё не написан.

Полезные инструменты Mac уже доступны: `yt-dlp 2025.10.22`, `ffmpeg 8.0`, `pandoc 3.7.0.2`, `pdftotext 26.03.0`, `pdftoppm`. `djvutxt` и `tectonic` отсутствуют. Это означает, что статья в PDF может пройти базовый текстовый fallback через Poppler, а DjVu и сборка TeX требуют отдельной зависимости; нельзя обещать DjVu или компиляцию авторского TeX только по текущей среде.

## YouTube: массовый импорт и видео

* Watch Later не перечисляется через YouTube Data API: `playlistItems.list` прямо возвращает `playlistOperationUnsupported` для watch later, а revision history подтверждает, что watch history и watch later недоступны API. Обычные приватные плейлисты требуют OAuth. [API errors](https://developers.google.com/youtube/v3/docs/errors), [revision history](https://developers.google.com/youtube/v3/revision_history), [playlists](https://developers.google.com/youtube/v3/docs/playlists).
* Интерфейс YouTube указывает максимум 5 000 отображаемых видео в одном плейлисте. Это лимит отображения, а не доказательство безопасного полного импорта через API; Watch Later нужно считать неподдержанным API-источником до проверки экспорта. [YouTube Help](https://support.google.com/youtube/answer/9209643).
* Google Takeout является пользовательским экспортом данных, включая YouTube, но официальная справка не обещает конкретный формат или поле, из которого FNMN сможет восстановить Watch Later. Поэтому Takeout — ручной fallback: пользователь экспортирует архив, Mac-адаптер принимает локальный архив и сохраняет исходную подборку; формат нужно проверить на одном реальном архиве. [Google Takeout](https://support.google.com/accounts/answer/3024190).
* `yt-dlp` умеет плоский обход плейлиста, JSON-метаданные, архив уже обработанных ID, список форматов и отдельную запись обычных или автоматически созданных субтитров. Локальная справка подтверждает `--flat-playlist`, `--dump-json`, `--download-archive`, `-F`, `--write-subs`, `--write-auto-subs` и `--sub-langs`. [yt-dlp README](https://github.com/yt-dlp/yt-dlp/blob/master/README.md).
* Авторизация не должна быть скрытой частью MVP: `yt-dlp` по умолчанию не читает cookies, а приватные и возрастные видео могут требовать их; проект предупреждает о риске блокировки аккаунта и о современных PO Token ограничениях. Не читать cookies или аккаунты без отдельного явного решения пользователя. [yt-dlp FAQ](https://github.com/yt-dlp/yt-dlp/wiki/FAQ), [YouTube extractor notes](https://github.com/yt-dlp/yt-dlp/wiki/Extractors/e6c51bd16bbfd532d05ca551eb408a95093ee9d3).
* Встроенный YouTube IFrame Player API поддерживает `seekTo(seconds, allowSeekAhead)` и сообщает, что переход идёт к ближайшему ключевому кадру, если нужный участок ещё не загружен; `start` имеет ту же оговорку и обычно может оказаться примерно до двух секунд раньше. Это делает точное восстановление возможным как запрос позиции, но не гарантирует кадр-в-кадр точность. Сохранять нужно время в секундах и периодически обновлять его по `getCurrentTime`, а UI должен явно принимать приблизительность. [IFrame API](https://developers.google.com/youtube/iframe_api_reference), [player parameters](https://developers.google.com/youtube/player_parameters).
* Embed умеет выбрать язык/показ captions через `cc_lang_pref` и `cc_load_policy`, но это настройки показа плеера, а не получение транскрипта в приложение. Для текста FNMN субтитры должны быть отдельным опциональным ресурсом, полученным адаптером; отсутствие субтитров не должно делать видео импортированным «готовым» к поиску. `yt-dlp` может записать auto-subs, но их доступность и язык зависят от конкретного видео.
* YouTube IFrame не даёт приложению универсальный ручной выбор качества: API сообщает доступные уровни и состояние, но конечный выбор зависит от адаптивного плеера, сети и самого видео. `-F` в `yt-dlp` перечисляет форматы скачивания, что относится к Mac-обработке, а не к качеству embedded playback. Поэтому в MVP не обещать фиксированное качество внутри WKWebView; сохранять исходный video ID и использовать официальный embed.

Практический первый smoke-test не требует аккаунта и cookies: взять публичное видео, получить `--dump-json --skip-download`, отдельно попробовать `--write-auto-subs --sub-langs en.* --skip-download`, затем открыть embed и сравнить сохранённую позицию с фактической. Массовый Watch Later тест возможен только после пользовательского Takeout или иного явно выбранного источника.

23 сентября 2026 года одно публичное видео уже проходит этим путём в сервисе. Пакет ставит `yt-dlp` 2026.8.19 и `yt-dlp-ejs` 0.8.0. Для «Me at the zoo» английский VTT пришёл, видеофайл не скачивается. Официальный `captions.download` по-прежнему не читает чужие дорожки. Массовый импорт и сверка секунды на самом плеере остаются открытыми.

## Веб-статьи, arXiv, LaTeX и DjVu

Первый article adapter должен обрабатывать обычную веб-статью в режиме, близком к Safari Reader: убрать навигацию, рекламу, футер и повторяющиеся элементы, сохранив заголовки, абзацы, списки, цитаты, ссылки, изображения, формулы и встроенное видео там, где они являются частью тела. Для этого не нужен самописный stdlib HTML parser: он разбирает теги, но не решает задачу выбора основного содержимого и легко оставляет всю страницу.

Рекомендуемый минимальный путь для Mac REST-сервиса — Python `trafilatura` как отдельный maintained dependency. Его extractor использует собственные rule-based filters с readability-lxml/jusText fallback, умеет metadata, headings/structure, formatting, links, images, tables и JSON/XML/Markdown output. Для FNMN нужно явно выключить comments, включить formatting/links/images, сохранять исходный HTML и URL, а результат преобразовывать в наш единый пакет блоков. [Trafilatura overview](https://trafilatura.readthedocs.io/en/latest/), [structured options](https://github.com/adbar/trafilatura/blob/master/docs/usage-python.rst).

Mozilla Readability остаётся хорошей альтернативой, если сервис будет Node.js: это алгоритм Firefox Reader View с `@mozilla/readability` и `jsdom`. Он возвращает очищенный HTML, сохраняет относительные URL при переданном base URL и требует отдельного sanitizer/CSP для untrusted output. Но сам Readability не является sanitizer и не гарантирует сохранение каждой формулы, iframe или lazy-loaded media; такие элементы нужно проверять и нормализовать после extraction. [Mozilla Readability](https://github.com/mozilla/readability).

Выбор для первого прохода: `trafilatura` + сохранённый raw HTML + небольшой post-processing adapter для `math`, `img`, `video`, `iframe` и ссылок. `readability-lxml` оставляется fallback внутри этого каскада, а не отдельным публичным форматом. Верификация должна прогнать реальные страницы с nested headings, KaTeX/MathJax, изображениями, iframe/video, таблицами и рекламными блоками; unsupported element сохраняется как ресурс или исходный HTML с причиной, а не молча удаляется.

Для arXiv предпочтителен адаптер исходников: `https://export.arxiv.org/e-print/<id>` отдаёт архив submission source, а `https://export.arxiv.org/api/query?id_list=<id>` — метаданные; 20 сентября 2026 года HEAD-проверка дала redirect на `/src/1706.03762` и `200 application/atom+xml` для API. Source сохраняет секции, формулы, labels, макросы и изображения лучше PDF, но это не готовый Markdown: нужно распаковать архив, определить главный `.tex`, раскрыть `\\input`/`\\include`, сохранить неизвестные макросы как исходник и не выполнять произвольный TeX. Публичность source также означает, что архив может содержать лишние файлы и комментарии; source нужно считать входными данными, а не доверенным кодом. [arXiv annual report](https://info.arxiv.org/about/reports/2023_arxiv_annual_report.pdf), [arXiv API](https://info.arxiv.org/help/api/index.html).

Fallback для PDF: сохранить оригинальный PDF, извлечь текст с `pdftotext -layout`, извлечь страницы/изображения при необходимости и проверять формулы по рендеру страниц. Poppler не восстанавливает исходную семантику TeX надёжно, поэтому этот путь нельзя называть faithful LaTeX extraction: математические блоки должны иметь provenance страницы и видимый исходный/рендерный fallback. В текущем Mac toolchain нет `djvutxt`; DjVu адаптер потребует установленного DjVuLibre или серверной конвертации и отдельного тестового корпуса.

Article adapter должен принимать URL/локальный файл и возвращать единый пакет: стабильный ID источника, название, исходный URL, разделы, атомарные блоки, изображения/ресурсы, формулы как исходный TeX только если они действительно пришли из HTML/исходника, и привязку каждого блока к DOM-фрагменту. Структурное деление выполняется на Mac; iOS читает уже подготовленный пакет. Для будущего PDF/arXiv adapter provenance и ограничения формул должны быть отдельными полями, а не маскироваться под обычную веб-статью.

## Foundation Models, classification и неизвестный API

Apple Foundation Models документирует `LanguageModelSession`, `@Generable`, `@Guide`, `DynamicGenerationSchema` и генерацию структурированных Swift-типов. `@Generable` применим к структурам и enum, а схема снижает риск malformed output и ручного JSON parsing; это гарантия формы результата, не истинности классификации или объяснения. В схему следует включать небольшой enum категорий и статус `unknown`/`needsReview`, затем проверять исходный текст отдельно. [Generable](https://developer.apple.com/documentation/foundationmodels/generable), [guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation), [classification example](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting).

Core AI — отдельный Apple framework для загрузки и исполнения собственных on-device моделей (`.aimodel`) с CPU/GPU/Neural Engine; он не является заменой Foundation Models и не даёт автоматически классификатор контента. Для первой классификации Foundation Models с `@Generable` проще и прямо соответствует выбранному стеку; Core AI понадобится только после выбора и подготовки собственной модели. [Core AI](https://developer.apple.com/documentation/CoreAI).

Название «TypeSafe Jev API» не найдено в проверенных Apple документации, локальных заметках или доступных SDK-описаниях. Не следует изобретать этот API или связывать его с `@Generable`; требуется уточнение названия/ссылки от автора. До этого классификация остаётся будущим исследованием, а не условием article MVP.

## Границы готовности

Готово к началу реализации: Xcode/iOS 27 SDK, нативный SwiftUI-клиент, Mac-подготовка статей и REST-передача единого пакета. Реальные блокеры — отсутствие кода/проекта, отсутствие DjVu/TeX runtime и неподдерживаемый Data API путь к Watch Later. Эти пункты требуют явного smoke-test и выбранного импорта, а не новых UI-слоёв.

Команды для повторной проверки окружения:

```sh
xcodebuild -version
xcodebuild -showsdks
xcrun --find swift
swift --version
yt-dlp --version
yt-dlp --help | rg -- '--flat-playlist|--write-auto-subs|--sub-langs|--list-formats|--download-archive'
command -v ffmpeg pandoc pdftotext pdftoppm djvutxt tectonic
```

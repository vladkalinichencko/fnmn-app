# Режимы чтения и формулы в HTML

Вопрос для FNMN: движки Reader Mode сводят страницу к статье одним общим методом или белым списком тегов вроде `article` / `d-article` / `dt-math`? Отдельно: есть ли у LaTeX на вебе носитель формулы, который не сводится к «эта строка похожа на математику»?

Проверено по первичным источникам ниже. Блоги и чужие пересказы не использовались.

## Mozilla Readability (Firefox Reader View)

Readability.js это отдельная библиотека того же алгоритма, что стоит за Firefox Reader View. https://github.com/mozilla/readability/blob/main/README.md

Процедура общая, не белый список издательских тегов. Метод `_grabArticle` ходит по DOM, убирает скрытые узлы и кандидатов по классам/id/role, набирает узлы из `DEFAULT_TAGS_TO_SCORE` (`section`, `h2`-`h6`, `p`, `td`, `pre`), считает content score по длине текста и запятым, поднимает score предкам и берёт лучшего кандидата. https://github.com/mozilla/readability/blob/main/Readability.js

Слово `article` встречается в регулярках положительных и «может быть кандидат» имён классов и id, а не как обязательный корневой тег страницы. https://github.com/mozilla/readability/blob/main/Readability.js

Строка `mathjax` тоже есть только в regexp `okMaybeItsACandidate`, то есть как исключение из удаления «маловероятных» блоков по имени, а не как разбор формул. https://github.com/mozilla/readability/blob/main/Readability.js

Тег `MATH` входит в `PHRASING_ELEMS`, поэтому MathML может остаться внутри текстовых абзацев при переписывании разметки. https://github.com/mozilla/readability/blob/main/Readability.js

Отдельного пути «это формула, извлеки TeX» в Readability нет. В `_isProbablyVisible` есть особый случай класса `fallback-image`, чтобы не выкидывать запасные картинки математики Wikimedia при `aria-hidden`. https://github.com/mozilla/readability/blob/main/Readability.js

Перед разбором скрипты и noscript снимаются с документа. https://github.com/mozilla/readability/blob/main/Readability.js

В `_prepArticle` безусловно чистятся `iframe`, `object`, `embed` и ряд форм-контролов. https://github.com/mozilla/readability/blob/main/Readability.js

`CANVAS`, `IFRAME` и `SVG` сознательно вынесены из списка phrasing-элементов в комментарии к `PHRASING_ELEMS`. https://github.com/mozilla/readability/blob/main/Readability.js

При чистке стилей ветка для `svg` останавливает обход внутрь SVG. https://github.com/mozilla/readability/blob/main/Readability.js

Неизвестные custom elements вроде `d-article` или `dt-math` нигде не перечисляются. Они не входят в `DEFAULT_TAGS_TO_SCORE`, поэтому сами по себе абзацами не оцениваются, но могут оказаться предками scored-узлов и получить накопленный score. https://github.com/mozilla/readability/blob/main/Readability.js

## Chromium DOM Distiller

DOM Distiller это открытый движок упрощённых статей Chrome, явно описанный как loosely based on Boilerpipe. https://github.com/chromium/dom-distiller/blob/master/README.md

Сначала DOM превращается в `WebDocument` обходом `DomConverter`, затем текстовые блоки классифицируются цепочкой фильтров `ArticleExtractor` (NumWordsRulesClassifier и эвристики соседства блоков). https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/ContentExtractor.java

`NumWordsRulesClassifier` помечает блоки content / not-content по числу слов и плотности ссылок у текущего, предыдущего и следующего блока. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/filters/english/NumWordsRulesClassifier.java

Есть узкий shortcut по ориентирам: если на странице ровно один видимый `ARTICLE`, обход начинается с него; иначе ищутся `[itemscope][itemtype*="Article"]` и `Posting`. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/DomUtil.java

Это сужение корня обхода, а не FNMN-стиль «если тег `dt-math`, то формула». После shortcut всё равно работает boilerpipe-классификатор. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/ContentExtractor.java

В `DomConverter` теги `SCRIPT`, `NOSCRIPT`, `IFRAME` и `svg` пропускаются и не попадают в документ. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/webdocument/DomConverter.java

`OPTION`, `OBJECT`, `EMBED`, `APPLET` тоже пропускаются. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/webdocument/DomConverter.java

Встроенное видео становится `WebVideo`. Известные эмбеды (картинки, Twitter, Vimeo, YouTube) вынимаются отдельными `EmbedExtractor`. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/webdocument/DomConverter.java

Поиск по исходникам Distiller не показывает обработчика MathML, MathJax или TeX. Math-теги издателей вроде `dt-math` там не названы.

Неизвестный custom element не входит в списки пропуска. Он проходит `builder.startElement` и отдаёт текстовые узлы в общий классификатор. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/webdocument/DomConverter.java

Сохраняемые вложенные теги структуры ограничены `UL`, `OL`, `LI`, `BLOCKQUOTE`, `PRE`. https://raw.githubusercontent.com/chromium/dom-distiller/master/java/org/chromium/distiller/webdocument/WebTag.java

## WebKit Reader / ArticleFinder

В публичном дереве `WebKit/WebKit` по прямым путям `Source/WebCore/page/Reader.cpp`, `Source/WebCore/page/ArticleFinder.cpp`, `Source/WebKitLegacy/mac/Misc/WebArticleFinder.mm` и каталогу `Source/WebCore/Modules/reading/` ответы `404`. https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebCore/page/Reader.cpp

Список модулей `Source/WebCore/Modules` через GitHub API не содержит каталога с именем про Reader или Article. https://api.github.com/repos/WebKit/WebKit/contents/Source/WebCore/Modules

На webkit.org описан продукт Safari Reader (в том числе Summarize), но не алгоритм извлечения статьи. https://webkit.org/blog/16188/webkit-features-in-safari-18-1/

Алгоритм Safari Reader / ArticleFinder из открытого дерева WebKit здесь восстановить нельзя. Выдумывать его не следует.

## MathML, MathJax, KaTeX: носители формулы

HTML Living Standard встраивает элемент MathML `math` как embedded / phrasing / flow content и отсылает семантику к спецификации MathML. https://html.spec.whatwg.org/multipage/embedded-content-other.html#mathml

MathML Core задаёт подмножество MathML, пригодное для реализации в браузерах, с упором на точный визуальный рендер. https://www.w3.org/TR/mathml-core/

MathML 4 пишет, что MathML Core покрывает (большую часть) Presentation Markup и детали показа математики в браузерах, а Full MathML в первую очередь добавляет Content MathML. https://www.w3.org/TR/mathml4/

То есть интероперабельная форма для веба это presentation / MathML Core вокруг `<math>`, а не угадывание TeX по тексту страницы.

MathML 3 в главе про annotation framework показывает параллельную разметку: presentation-дерево плюс `<annotation encoding="application/x-tex">` с исходным TeX. https://www.w3.org/TR/MathML3/chapter5.html

Документация MathJax говорит, что популярные аннотации вроде TeX кладут в `semantics`, и меню «Show Math As → Annotations» их отдаёт. https://docs.mathjax.org/en/latest/input/mathml.html

В опциях меню MathJax для типа TeX перечислены метки `TeX`, `LaTeX` и `application/x-tex`. https://docs.mathjax.org/en/latest/options/menu.html

KaTeX при сборке MathML кладёт исходный TeX в `<annotation encoding="application/x-tex">` внутри `<semantics>`. https://raw.githubusercontent.com/KaTeX/KaTeX/v0.16.11/src/buildMathML.js

По умолчанию KaTeX отдаёт `htmlAndMathml`: HTML для экрана и MathML для доступности. https://katex.org/docs/options.html

Отдельный исторический носитель сырого TeX до рендера это `<script type="math/tex">` (и `math/tex; mode=display`). Расширение KaTeX `mathtex-script-type` ищет `script.type`, совпадающий с `/math\/tex/i`, и рендерит `script.text`. https://github.com/KaTeX/KaTeX/tree/main/contrib/mathtex-script-type

Документация обновления MathJax v3 показывает тот же селектор `script[type^="math/tex"]` как пример совместимости с разметкой MathJax 2; в v3 это уже не поведение по умолчанию, а явный `renderActions`. https://docs.mathjax.org/en/latest/upgrading/v2.html

Универсальный способ назвать формулу без эвристики «строка похожа на math» это стандартные носители: элемент `<math>`, annotation `encoding="application/x-tex"`, при необходимости `alttext` у `<math>`, и скрипт `type` с префиксом `math/tex`. Обёрток издателя вроде `dt-math` в этих спецификациях нет.

## Trafilatura

FNMN уже зависит от Trafilatura. README описывает rule-based extractor основного текста с fallback на jusText и readability-lxml. https://github.com/adbar/trafilatura/blob/master/README.md

Основной путь: чистка дерева, затем `extract_content` по набору `BODY_XPATH` (часто `article` / `main` / `section` / `div` с типичными class/id), разбор узлов из каталога тегов, при коротком результате идут recovery и внешние fallback. https://raw.githubusercontent.com/adbar/trafilatura/master/trafilatura/main_extractor.py

`BODY_XPATH` явно перечисляет HTML `article` и распространённые имена content/body, но не Distill-теги `d-article` / `dt-article` / `dt-math`. https://raw.githubusercontent.com/adbar/trafilatura/master/trafilatura/xpaths.py

В текущем `master` перед удалением шума вызывается `recover_math`: для каждого `math` берётся `annotation[@encoding="application/x-tex"]`, иначе `alttext`, и LaTeX переносится в `tail` как `\(...\)` или `\[...\]`. https://raw.githubusercontent.com/adbar/trafilatura/master/trafilatura/htmlprocessing.py

Закреплённая в проекте trafilatura 2.0.0 этой функции не содержит. Там `math` сразу входит в `MANUALLY_CLEANED` и удаляется вместе с поддеревом. `server/requirements.txt`, установленный пакет 2.0.0.

В `master` после salvage тег `math` всё равно входит в `MANUALLY_CLEANED` и удаляется. Исходник к этому моменту уже лежит в `tail`. https://raw.githubusercontent.com/adbar/trafilatura/master/trafilatura/settings.py

Туда же входят `script`, `iframe`, `canvas`, `svg`, `figure` (figure можно сохранить, если включены картинки). https://raw.githubusercontent.com/adbar/trafilatura/master/trafilatura/settings.py

Отдельного разбора `script type="math/tex"` в `recover_math` нет. Путь математики у Trafilatura это MathML annotation / `alttext`, затем выброс самого `<math>`.

Custom elements издателя Trafilatura как особые корни статьи не называет. Неизвестный тег либо попадёт под xpath/очистку по общим правилам, либо останется шумом вне `TAG_CATALOG`. https://raw.githubusercontent.com/adbar/trafilatura/master/trafilatura/settings.py

## Суждение для FNMN

Продакшен-движки статьи (Readability, DOM Distiller, Trafilatura) делают одно и то же по роду работы: общий scorер или xpath/эвристика основного текста плюс чистка boilerplate. Они не держат длинный белый список фирменных тегов сайта.

Узкий ориентир `article` / schema.org Article у Distiller и xpath на `article` у Trafilatura это вспомогательный landmark внутри общей процедуры, а не аналог наших `d-article` / `dt-article` / `dt-math`.

Особые имена Distill и прочих обёрток у FNMN это site wrapper. Их не стоит тащить в ядро парсера как будто так делают Reader Mode.

Формулу индустрия ищет не по «похоже на LaTeX», а по маленькому набору стандартных носителей: `<math>` (presentation / MathML Core), `annotation encoding="application/x-tex"`, иногда `alttext`, и `script type="math/tex"`. Текущий `master` Trafilatura уже берёт annotation и `alttext`. Поставленная сюда 2.0.0 формулу выбрасывает. Парсер веб-статьи теперь делает то же с носителями, а регион статьи выбирает по оценке текста, как Readability. Имена `dt-math` и `d-article` в нём не участвуют. Живой кадр фигуры по-прежнему отдельный: эти движки скрипты снимают.

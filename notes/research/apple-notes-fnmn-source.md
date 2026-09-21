# FNMN source from Apple Notes

Source note: `Vibecoding`  
Folder: `Projects`  
Note ID: `x-coredata://BC927388-BCB6-4C2B-898F-080E89C88E7C/ICNote/p6093`  
Fetched modified timestamp: `2026-09-19T10:52:23.000Z`

The requested folder `VibeCoding` was not present. The matching note was found globally as `Vibecoding` in `Projects`. The source below starts at the note's `FNMN` heading and runs to the end of the note.

## FNMN

Twitter for learning
Doomscroll through your books

Собрать все сайты с видео и статьями в одно место
iPasOS + iOS 27
супермодульная архитектура
Liquid Glass, только нативные предустановленные элементы и стили. ни грамма дополнительных swiftui modifiers etc., минимальные изолированные «микросервисы», минимальный & минималистичный интерфейс кода
 
Настроить автоматический парсинг и переформатирование контента через локальный сервер (на маке)
Интегрировать транскрипты YouTube к видео, тоже с поиском и иерархией. scrabbing transcripts, через youtube API
перевод из ссылок на разные сервисы/сайты – забираем код, форматируем, сохраняем в cloudkit; pdf и всякие нетривиальные – через сервер на ноуте; включая все типы изображений и видео, все embedded штуки, по типу distill
отображать контент в markdown, со всеми интерактивными элементами тоже

разделение по категориям – сначала автоматически (хз как), а потом можно вручную менять
секции continue reading & up next
поиск full text search + semantic
идентификаторы: закладки/звездочки, прочитанно/непрочитано и насколько прочитанно, убрать/удалить
Добавить иерархическую навигацию внутри контента (разделение на блоки по параграфам, не учитывая переносы формул на след строку, pinch to zoom для перехода в оглавление)
Сохранять ссылку на оригинал текста
отображать место, где пользователь закончил читать, внутри документа
Реализовать настройку интерфейса: ресайз текста, фон, отступы по краям
возможность скрывать предложения выделением, выделять для закладок, sidenotes – комментарии к выделениям на полях

Реализовать функцию «Send to ChatGPT/Claude/Gemini».
Реализовать "Share to FNMN" из Twitter, YouTube, Substack, Safari, ChatGPT, ArXiv и т.д. (есть интеграция с ChatGPT Projects?)

Провести оптимизацию SwiftUI
Добавить поддержку App Intents
Use Apple Intelligence, Foundation Models, CoreML & CoreAI APIs
TypeSafe Jev API

Убирать лишние предложения – внутри параграфов и в контексте побольше
разделять текст на отдельные мысли
Добирать объяснения
убирать ненужный математический формализм
Пояснять причины выбора формул
не вводить ненужные термины
Объяснять, где и к чему относится знание «в масштабе»
все переписывания – в модель подается в контекст весь окружающий контент

Интегрировать ленту а-ля Twitter. каждый пост – это один небольшой факт: переход доказательства, факт из параграфа
в стиле человека, который постит, как экспозиция, маленький самостоятельный рассказ
пост линкается к той части книги, откуда был взят
если маленькими фактами покрыт полностью большой кусок текста, или все задание, значит можно написать большой пост, всё это соединяющий
Добавить мультимодальные объяснения с визуализациями (HTML/SwiftUI шаблоны с мэппингом на формулы, подбор типа визуализации под вход/выход)
задания – тоже подразделяются на подтемы, если нужно
задания имеют разные элементы интерфейса для ввода: выбор ответа, специализированные поля ввода, свободный ответ
тред с заданием продолжается если пользователь что-то недопонял
кнопки рекций: interesting / already know / incomprehendable etc.
все комменты, реакции и выводы – в self-impoving meta-harness
NEW ты постишь идеи/вопросы – агент на них реагирует/отвечает
NEW вместо того чтобы писать факт, агент задаёт наводящий сократический вопрос/даёт ситуацию, приводящую к этому знанию
типы ответов модели:
keeping_together — Тег-вопрос к классу — «…да?», «…вы согласны?»
relate_to_another — Просьба связать свой ответ с репликой другого ученика
restating — Дословное или почти дословное повторение слов ученика
revoicing — Перефразирование идеи ученика с новой терминологией
press_accuracy — Запрос факта или конкретного значения — «что», «сколько», «когда»
press_reasoning — Запрос обоснования или объяснения — «почему», «как», «докажи»
explain — Тьютор излагает правило или закон — не пересказ ученика
reveal — Тьютор прямо называет ответ или выполняет ключевой шаг
acknowledge — Нейтральное подтверждение без оценки — «ок», «понятно», «давай дальше»
evaluate — Краткая оценка правильности — «верно», «молодец», «нет»
 FNMN Editing Ontology v0.1. Важно: это multi-label система. Абзац может одновременно иметь MULTIPLE_IDEAS + UNDEFINED_TERM + REDUNDANT_BACKGROUND.
У каждого правила одна структура:
scope → issue → detector → action → constraints
А разрешённые базовые actions я бы намеренно сделал маленькими:
COPY · DELETE · TRIM · SPLIT · MERGE · REORDER · REPHRASE · EXPLAIN · DEFINE · EXEMPLIFY
Это расширение очень удачного COPY / REPHRASE / SPLIT / DELETE из document-level planning.
INFORMATION STRUCTURE — что именно и в каком порядке говорится
I01 MULTIPLE_IDEAS · paragraph Вопрос: содержит ли блок две или больше мысли, которые можно понять независимо? Action: SPLIT.
Плохо: «Contrastive learning maximizes agreement between views, while large batches are commonly used because they provide more negatives, although this creates substantial memory requirements.»
Лучше: сначала отдельный блок про objective. Потом отдельный про negatives/batch size.
I02 BURIED_MAIN_CLAIM · paragraph/section Главная мысль появляется только после длинной подготовки? Action: REORDER + TRIM.
I03 DETAIL_BEFORE_IDEA Детали метода идут до того, как читателю сказали, что метод вообще пытается сделать? Action: REORDER.
I04 PREREQUISITE_AFTER_USE Понятие используется раньше необходимого prerequisite? Action: REORDER или DEFINE.
I05 MISSING_BRIDGE Между двумя утверждениями пропущен смысловой переход?
Плохо: «Loss decreases. Therefore the representation becomes invariant.»
Здесь therefore может скрывать целую отсутствующую причинную связь.
Action: EXPLAIN.
I06 DUPLICATED_IDEA Этот смысл уже был сообщён рядом без существенного нового содержания? Action: DELETE/TRIM.
I07 MISPLACED_DETAIL Информация полезна, но находится не там, где нужна? Action: REORDER.
I08 PARAGRAPH_NO_SINGLE_PURPOSE Можно ли одним коротким предложением сказать, зачем существует этот параграф? Если нет, вероятен SPLIT/REWRITE.
Это в основном слой organization/coherence/clarity, которые устойчиво появляются в revision taxonomies.
SEMANTIC COMPLETENESS — чего читателю не хватает
C01 UNDEFINED_TERM · term Встречается ли важный термин, значение которого нельзя восстановить из локального контекста? Action: DEFINE либо retrieve предыдущего определения.
C02 UNEXPLAINED_SYMBOL · symbol Используется ли математический символ до определения?
C03 UNKNOWN_REFERENCE Понятно ли, что означает this, it, the former, this objective, the method?
Плохо: «This improves it significantly.»
Лучше: «Increasing the number of negatives improves the contrastive objective…»
C04 MISSING_PREMISE Для вывода требуется предположение, которое автор оставил неявным?
C05 IMPLICIT_INFERENCE Между A и B требуется нетривиальный шаг рассуждения?
C06 CLAIM_WITHOUT_REASON Автор утверждает X works / X is important / X follows, но не объясняет почему? Action: EXPLAIN.
Это близко к Claim/Ideas и Warrant/Reasoning/Backing из revision taxonomies.
C07 RESULT_WITHOUT_MECHANISM Описан эффект, но не механизм.
C08 MECHANISM_WITHOUT_PURPOSE Объясняется, как что-то работает, но не зачем это нужно.
C09 EXAMPLE_WITHOUT_RULE Есть пример, но не сформулирована общая идея.
C10 RULE_WITHOUT_EXAMPLE Абстрактное понятие существенно легче понять на маленьком примере? Action: EXEMPLIFY.
C11 EXCEPTION_NOT_STATED Утверждение звучит универсально, хотя из контекста видны ограничения/conditions.
C12 ASSUMPTION_TOO_REMOTE Важное условие было определено значительно раньше и необходимо вернуть в локальный context.
Это уже особенно важно для книг: здесь retrieval по документу лучше, чем свободная генерация модели.
SALIENCE / COMPRESSION — что можно не заставлять тебя читать
S01 LOW_INFORMATION Добавляет ли предложение новую информацию вообще?
S02 RHETORICAL_FILLER Можно удалить фразу без потери proposition?
Например:
«It is worth noting that one very important thing to understand is that…»
→ непосредственно утверждение.
S03 REDUNDANT_EXAMPLE После того как идея уже ясна, добавляет ли ещё один пример что-нибудь?
S04 REDUNDANT_RESTATEMENT Автор повторил мысль другими словами, не добавив nuance?
S05 EXCESSIVE_MOTIVATION Нужен ли весь background для понимания текущей идеи?
S06 EXCESSIVE_QUALIFICATION Есть ли оговорки, которые не меняют практически полезный смысл? Тут надо быть осторожным: may, under assumption X, only when часто нельзя удалять.
S07 LOW_RELEVANCE_TO_FEED_INTENT Соответствует ли блок текущей теме пользователя?
Это уже не свойство качества текста, а ranking property FNMN.
S08 LOW_NOVELTY_FOR_USER Содержит ли блок информацию, которую пользователь уже много раз видел?
S09 HIGH_INFORMATION_DENSITY Напротив, нельзя ли этот блок сокращать вообще, потому что почти каждое предложение несёт отдельную информацию?
То есть output классификатора здесь не обязательно «исправь». Иногда правильный ответ COPY.
ACCESS показывает, что length, amount of paraphrasing, lexical complexity и syntactic complexity полезно рассматривать как независимые регулируемые параметры, а не один scalar «simplicity».
LOCAL EXPRESSION — предложение само тяжело читать
L01 OVERLONG_SENTENCE Есть ли несколько независимых clauses, которые проще воспринимать последовательно? Action: SPLIT.
L02 DEEP_NESTING Нужно ли держать несколько вложенных зависимостей в working memory?
L03 LONG_DISTANCE_DEPENDENCY Субъект и сказуемое/определяемое слово и определение слишком далеко друг от друга?
L04 OPAQUE_NOMINALIZATION Действие спрятано в существительное и из-за этого непонятно, кто что делает.
L05 UNNECESSARY_PASSIVE Passive скрывает важного агента.
L06 LEXICAL_COMPLEXITY_WITHOUT_GAIN Есть более обычное слово с тем же техническим смыслом?
L07 AMBIGUOUS_WORDING Фраза имеет несколько разумных интерпретаций.
L08 REFERENT_OVERLOAD В предложении слишком много сущностей, и дальше непонятно, какая из них участвует в действии.
L09 TOO_MANY_COORDINATED_ITEMS Одно предложение перечисляет несколько причин/следствий/условий, которые лучше представить отдельно.
L10 NOTATION_INTERRUPTS_PROSE Можно ли вынести формулу/определение так, чтобы prose и math не мешали друг другу?
Здесь как раз уместны классические операции simplification: lexical substitution, deletion, splitting и paraphrasing. Hybrid systems даже специально разделяли rule-based splitting/deletion и neural paraphrasing вместо одной end-to-end операции.
EXPLANATION QUALITY — текст корректен, но плохо обучает
Это уже часть, которую академические simplification taxonomies покрывают хуже, поэтому здесь я расширяю их специально под FNMN.
E01 NO_BIG_PICTURE Перед деталями понятно, какую проблему решаем?
E02 NO_CAUSAL_EXPLANATION Текст сообщает корреляцию/процедуру, но не causal/mechanistic intuition.
E03 NO_CONCRETE_INSTANCE Абстракцию существенно легче понять на минимальном конкретном случае?
E04 EXAMPLE_TOO_COMPLEX Пример сам содержит лишнюю сложность.
E05 ANALOGY_WITHOUT_MAPPING Есть аналогия, но не сказано, какие части аналогии соответствуют реальным объектам.
E06 FORMULA_WITHOUT_SEMANTICS Дана формула, но не объяснено словами, что делают её части.
E07 SEMANTICS_WITHOUT_FORMALIZATION Напротив, для точного технического понимания полезно показать математическую форму.
E08 NO_CONTRAST Понятие легче определить через отличие от соседнего понятия?
Например batch GD vs SGD, invariance vs equivariance.
E09 NO_FAILURE_CASE Можно ли неправильно понять правило как универсальное? Если да, полезен counterexample.
E10 EXPLANATION_WRONG_LEVEL Объяснение предполагает слишком много или слишком мало предварительных знаний.
Последний особенно важен для тебя: понятность нельзя оценивать только по grade level текста. Техническому читателю длинное слово eigenvalue может быть легче, чем пара предложений бытового пересказа.
TERMINOLOGY / DOCUMENT MEMORY
T01 TERMINOLOGY_DRIFT Одна сущность внезапно называется другим термином.
T02 TERM_COLLISION Одинаковое слово используется в двух разных смыслах.
T03 AUTHOR_SPECIFIC_DEFINITION Термин имеет специальное определение именно в этом документе. Constraint: не заменять его общей LLM-дефиницией.
T04 ACRONYM_WITHOUT_EXPANSION Аббревиатура не определена локально и пользователь может её не знать.
T05 SYMBOL_DRIFT Один объект обозначается разными символами либо символ переиспользован.
T06 LOST_CROSS_REFERENCE После rewrite остались the previous result, Eq. 7, below, но соответствующий объект исчез/переместился.
T07 DEFINITION_DEPENDENCY Для самостоятельного feed item требуется подтянуть определение из другого блока.
T08 CONTEXT_DEPENDENT_BLOCK Можно ли понять block отдельно от предыдущего? Это очень важный score именно для Twitter-like feed.
FACTUAL / LOGICAL SAFETY
Тут transformation должен быть консервативным. В simplification literature отдельно фиксируют ошибки insertion, deletion и substitution: модель может добавить неподдержанное утверждение, удалить критическую информацию или заменить исходный смысл другим.
F01 UNSUPPORTED_INSERTION Rewrite добавил proposition, которого нет в source/context.
F02 MATERIAL_DELETION Удалено условие, причина, результат или ограничение, которое меняет содержание.
F03 SEMANTIC_SUBSTITUTION Утверждение заменилось похожим, но не эквивалентным.
F04 QUANTIFIER_CHANGE some → all, often → always, can → will.
F05 NEGATION_CHANGE Потерялось not, except, unless.
F06 EPISTEMIC_STRENGTH_CHANGE may suggest → shows, likely → certainly.
F07 CONDITION_LOSS «при X» превратилось в безусловное утверждение.
F08 CAUSALITY_INVENTED A correlates with B превратилось в A causes B.
F09 MATH_CHANGED Формула, variable, inequality, index или constant изменились.
F10 CITATION_SCOPE_CHANGED После rewrite citation выглядит так, будто подтверждает другое утверждение.
Эти десять я бы запускал после генерации как verifier.
PRESENTATION / FEED TRANSFORMATION
Это уже практически FNMN-specific.
P01 ATOMIC_TAKE_POSSIBLE Можно ли превратить часть текста в один самостоятельный feed item?
P02 THREAD_REQUIRED Смысл слишком зависим от последовательности, поэтому нужны 2–5 связанных карточек, а не одна.
P03 KEEP_ORIGINAL Авторская формулировка уже оптимальна. Ничего не делать.
Это очень важный класс. Иначе generator будет портить хороший текст просто потому, что обязан что-нибудь изменить.
P04 HIGHLIGHT_CORE Можно ничего не переписывать, а просто визуально выделить 1–2 ключевых предложения.
P05 COLLAPSE_DETAIL Основную мысль показать сразу, derivation/details спрятать под Expand.
P06 SHOW_DEFINITION_INLINE Термин можно раскрывать маленькой inline-card.
P07 SHOW_PREVIOUS_CONTEXT Нужно показать короткий предыдущий block.
P08 ORIGINAL_ON_DEMAND Transformation допустим только если оригинал всегда доступен одним нажатием.

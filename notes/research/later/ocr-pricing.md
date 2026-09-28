# Стоимость OCR для книги

Состояние цен проверено 17 сентября 2026 года. Точный PDF книги *The Principles of Deep Learning Theory* здесь не проверялся, поэтому расчёт ниже использует условный объём 500 страниц. Для другой длины действует тот же множитель: цена за страницу × число страниц.

## DeepSeek OCR и OCR2

Официальный репозиторий DeepSeek публикует веса и код `DeepSeek-OCR` под MIT и инструкцию запуска через Transformers/vLLM. В README указаны CUDA 11.8+, PyTorch 2.6 и пример производительности около 2500 токенов/с на A100-40G; для PDF модель принимает изображения страниц и prompt `Convert the document to markdown` ([официальный репозиторий](https://github.com/deepseek-ai/DeepSeek-OCR), [DeepSeek-OCR2](https://github.com/deepseek-ai/DeepSeek-OCR-2)). Это стоимость вычислений и хранения, а не бесплатный hosted OCR: цена A100, аренды, очереди и инженерного времени в репозитории не указана.

Официальный DeepSeek API на текущей странице цен перечисляет `deepseek-flash` (DeepSeek-V4.1-Flash) и `deepseek-v4-pro`, а не модели `DeepSeek-OCR` или `DeepSeek-OCR2`. Flash имеет vision, но тарифицируется по токенам: input cache miss $0.15 за 1M токенов off-peak и $0.30 peak, output $0.60 и $1.20 соответственно; peak: 01:00–04:00 и 06:00–10:00 UTC по будням ([официальные модели и цены](https://api-docs.deepseek.com/quick_start/pricing/), [официальный Files API](https://api-docs.deepseek.com/guides/files_api/)). Поэтому официального per-page OCR тарифа не найдено. Для OCR через Flash нужно отправлять изображения и считать фактические input/output tokens. Формула: `cost = input_tokens/1M × input_rate + output_tokens/1M × output_rate`; стоимость 500 страниц заранее не выводится из числа страниц.

## Коммерческий ориентир: Mistral OCR

Официальный Mistral OCR 4.0/4.1 стоит $4 за 1000 страниц, либо $0.40 за 1000 страниц при cache hit; annotated pages стоят $5 за 1000 ([цены](https://docs.mistral.ai/inference/pricing/), [возможности OCR](https://docs.mistral.ai/api/endpoint/ocr)). Для 500 страниц это $2 без cache hit, $0.20 при cache hit или $2.50 для annotated pages. API умеет выбирать страницы, отдавать таблицы в Markdown или HTML, включать page/word/block confidence scores и bounding boxes. Это делает проверку возможной, но не даёт гарантии lossless-распознавания формул, двухколоночной верстки или таблиц.

Для книги с крупными формулами и multi-column tables нельзя считать один успешный HTTP-ответ доказательством качества. Нужно сохранять исходный PDF, OCR по страницам и confidence, проверять число страниц, заголовки, формульные delimiters и число строк таблиц, а сомнительные страницы повторять с другим prompt или crop. Изменённый результат не должен заменять исходную редакцию; ручная проверка остаётся обязательной для страниц с формулами, схемами и сложными таблицами.

## Оплата из России

Официальные страницы DeepSeek подтверждают баланс и пополнение API, но в доступной документации не указывают допустимые страны выпуска карт или конкретную платёжную сеть. Отсутствие баланса обозначается Payment Required. [Ошибки API](https://api-docs.deepseek.com/quick_start/error_codes/).

Mistral официально требует credit card либо cloud billing через AWS/Azure для активации платного API, но не обещает поддержку российской карты и не публикует в просмотренной документации список стран ([создание организации](https://docs.mistral.ai/getting-started/quickstarts/admin/create-organization)). Поэтому по этим источникам нельзя утверждать, что карта российского выпуска сработает. До любой оплаты нужно отдельно проверить доступность платежа в аккаунте; платные вызовы и регистрацию в рамках исследования не выполнять.

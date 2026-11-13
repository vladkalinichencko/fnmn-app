# Digest classifier evaluation

Исследование классификатора дайджеста: статистика стора, разметка,
эксперименты с моделями и порогами. Отчёт с выводами — `REPORT.md`.

## Состав

- `REPORT.md` — итоговый отчёт: метрики NLI/e5/Qwen, датасеты, рабочие точки.
- `data/` — размеченные данные и сырые результаты прогонов:
  - `evalset.json` — 94 поста с канонической разметкой (10 классов).
  - `digest-offtopic-eval.jsonl` — 140 случайных постов стора
    (69 off-topic / 71 on-topic) — датасет для abstention-метрики.
  - `gold_canonical.json` — разметка evalset по id.
  - `interests.jsonl` — кандидаты по «интересам» (k-pop, обложки и т.п.).
  - `tricky.json` — запутанные контрольные тексты.
  - `labels.json`, `scores.json`, `nli_results.json`, `offtopic_preds.json`,
    `offtopic_eval.json`, `offtopic_sample.json` — промежуточные результаты.
- `scripts/` — воспроизводимые прогоны (ad-hoc, читаются как журнал
  экспериментов): eval по моделям/темам/порогам, формулировки тем,
  off-topic acceptance, обогащение контекстом/комментариями, Qwen vs e5.

## Окружение

Скрипты рассчитаны на `.venv` сервера + опциональные ML-зависимости:
`torch`, `transformers`, `sentence-transformers`, `numpy`.
Модели тянутся из HF cache: `Qwen/Qwen3-Embedding-0.6B` (текущий
скорер, `digest/topics.py`), `intfloat/multilingual-e5-*`,
`MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7`,
`joeddav/xlm-roberta-large-xnli` (удалены из кэша после экспериментов).

Данные постов брались из `~/Library/Application Support/FNMN/digest-out/posts.jsonl`
(симлинк на iCloud `digest-out`).

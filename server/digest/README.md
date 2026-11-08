# Дайджест соцсетей

Mac следит за выбранными каналами Telegram и аккаунтами X, копит посты и дважды в день кладёт дайджест
поставкой в папку FNMN. Приложение читает его вкладкой Digest; замысел и границы — в
[notes/research/social-digest.md](../../notes/research/social-digest.md).

## Что запускается

```sh
server/digest/fnmn-digest.sh on       # агенты: монитор каждые 2 часа, сборка в 08:00 и 20:00, обучение в 21:00
server/digest/fnmn-digest.sh status   # агенты и три последние поставки
server/digest/fnmn-digest.sh monitor  # прочитать все источники один раз, сейчас
server/digest/fnmn-digest.sh build    # собрать дайджест, если время пришло
server/digest/fnmn-digest.sh train    # обучить классификатор на журнале реакций
```

Вручную, из `server/`:

```sh
../.venv/bin/python -m digest.monitor --only x/karpathy --verbose
../.venv/bin/python -m digest.build --force
```

## Вход в сети

X и Instagram читаются постоянным профилем Chromium на сеть: `server/digest/profiles/<network>/`.
Один раз на Mac:

```sh
server/digest/fnmn-digest.sh login x
server/digest/fnmn-digest.sh login instagram
```

Открывается окно Chrome со страницей входа; после входа нажать Enter в терминале. Дальше всё идёт headless
на этом профиле. Dia не трогается: его cookie зашифрованы ключом браузера и принадлежат живой сессии.

Telegram публичные каналы читаются без входа через `t.me/s/<channel>`.

## Подписки

`subscriptions.json` рядом: папки в порядке разделов журнала и источники.

```json
{"folders": ["ml", "design"], "sources": [
  {"id": "x/karpathy", "network": "x", "handle": "karpathy", "name": "Andrej Karpathy", "folders": ["ml"]},
  {"id": "telegram/durov", "network": "telegram", "channel": "durov", "name": "Pavel Durov", "folders": ["tech"]}
]}
```

## Классификатор

```sh
uv pip install --python ../.venv/bin/python -r ../requirements.txt
../.venv/bin/python -m digest.train --dry-run   # сколько строк и каких папок
../.venv/bin/python -m digest.train             # out/classifier.mlmodel + out/model.json
```

Модель учится на тексте постов: метка — первая папка источника; скрытый пост не идёт в обучение, сохранённый
считается трижды, открытый дважды. Тренер запускается агентом в 21:00, после вечерней сборки; следующая сборка
кладёт модель в поставку, телефон считает её `NLModel`.
Пока строк меньше двадцати, дайджест едет без модели, и журнал раскладывается по папкам источников.

## Что проверено

- Разбор `t.me/s` — на живой странице `t.me/telegram` (сохранена в `fixtures/telegram.html`).
- Ответ `cdn.syndication.twimg.com/tweet-result` — живой (fixtures/tweet-20.json); формы с фото, цитатой и
  ответом — по типам react-tweet, синтетические.
- Разметка ленты X и страницы Instagram — не проверена вживую: нужен вход. Первый `monitor` после `login` —
  и есть проверка; парсеры держатся тестами на фикстурах.

## Чего здесь нет

Лайков и ответов от имени читателя (система только читает), видео внутри приложения (постер и ссылка),
медиа цитируемого поста, повтор-пост как отдельный вид (приходит телом оригинала), редактирования подписок
из приложения.

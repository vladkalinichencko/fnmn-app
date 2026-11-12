# Дайджест соцсетей

Mac следит за выбранными каналами Telegram и аккаунтами X, копит посты и дважды в день кладёт дайджест
поставкой в папку FNMN. Приложение читает его вкладкой Digest; замысел и границы — в
[notes/research/social-digest.md](../../notes/research/social-digest.md).

## Что запускается

```sh
server/digest/fnmn-digest.sh on       # агенты: монитор каждые 2 часа, сборка в 08:00 и 20:00
server/digest/fnmn-digest.sh status   # агенты и три последние поставки
server/digest/fnmn-digest.sh monitor  # прочитать все источники один раз, сейчас
server/digest/fnmn-digest.sh build    # собрать дайджест, если время пришло
server/digest/fnmn-digest.sh scan     # записать в subscriptions.json подписки профилей
```

Вручную, из `server/`:

```sh
../.venv/bin/python -m digest.monitor --only x/karpathy --verbose
../.venv/bin/python -m digest.build --force
```

## Вход в сети

X, Instagram и Telegram читаются постоянным профилем Chromium на сеть: `server/digest/profiles/<network>/`.
Один раз на Mac:

```sh
server/digest/fnmn-digest.sh login x
server/digest/fnmn-digest.sh login instagram
server/digest/fnmn-digest.sh login telegram
```

Открывается обычное окно Chrome со страницей входа; после входа закрыть Chrome (Cmd-Q) и нажать Enter в
терминале. Дальше всё идёт headless на этом профиле. Dia не трогается: его cookie зашифрованы ключом
браузера и принадлежат живой сессии.

Telegram публичные каналы открываются и без входа через `t.me/s/<channel>`; профиль нужен для каналов,
которые без сессии не показывают ленту.

## Подписки

`subscriptions.json` рядом: папки в порядке разделов журнала и источники.

```json
{"folders": ["ml", "design"], "sources": [
  {"id": "x/karpathy", "network": "x", "handle": "karpathy", "name": "Andrej Karpathy", "folders": ["ml"]},
  {"id": "telegram/durov", "network": "telegram", "channel": "durov", "name": "Pavel Durov", "folders": ["tech"]},
  {"id": "x/feed", "network": "x", "scope": "recommendations", "folders": ["ml"]}
]}
```

`fnmn-digest.sh scan` проходит по подпискам всех трёх сетей и сверяет `sources` с тем, что
профили показывают сейчас: X — страница Following своего аккаунта, Instagram — диалог Following
(скроллится до конца), Telegram — каналы из сессии `telegram` CLI (`telegram chats --type channel`;
канал без публичного username читать нечем — у `t.me` нет его страницы). Найденный сканом источник
помечается `scanned` и при следующем скане убирается, если отписка случилась; источник, написанный
руками, остаётся всегда, а его папки, имя и scope сохраняются при любом скане.

`scope` выбирает, что читает источник. По умолчанию (`"subscriptions"` или без поля) — посты
конкретного аккаунта. `"recommendations"` читает ленту рекомендаций самой сети: для X это вкладка
For you (`x.com/home`, автор берётся из каждого поста), для Instagram — домашняя лента, для
Telegram такого режима нет, и источник падает с объяснением. Лента задаётся источником без
`handle`/`channel`, например `x/feed`; папки у него работают как у обычного.

## Темы

Разделы журнала — это `folders` подписок и `folders` каждого источника: пост попадает в папку
источника, из которого его прочитали. Классификатора и журнала реакций здесь нет.

## Повтор картинки

Приложение зовёт `POST /digest/refresh` с `{"post_id": "..."}`; Mac заново читает этот пост профилем сети
и отдаёт файлы через `GET /digest/media/<name>`. Только этот пост, без новой поставки.

## Что проверено

- `scan`, `monitor` и `build` прогнаны вживую на всех трёх сетях: 458 источников в `subscriptions.json`,
  сборка `digest-2026-11-12T16-48-34Z.tar` (78 постов) доехала до папки FNMN.
- Instagram-скан добирает Following не полностью: диалог виртуализирован, список догружается порциями.
- X в headless проходит Cloudflare только с живым `cf_clearance`; при протухании нужен один headed-прогрев
  профиля (`reader.ensure("x", headed=True)` и открыть x.com).

## Чего здесь нет

Лайков и ответов от имени читателя (система только читает), видео внутри приложения (постер и ссылка),
медиа цитируемого поста, повтор-пост как отдельный вид (приходит телом оригинала), редактирования подписок
из приложения.

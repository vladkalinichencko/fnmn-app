# Подключение REED к Mac через Tailscale Funnel

Funnel на бесплатном Tailscale Personal публикует локальный сервис Mac по HTTPS-адресу `*.ts.net`. Адрес доступен любому в интернете, поэтому REED требует отдельный bearer-токен на `/health` и `/jobs`. Трафик Funnel имеет ограничение полосы. Mac должен оставаться включённым и подключённым к интернету. [Условия Funnel](https://tailscale.com/docs/features/tailscale-funnel), [бесплатный Personal](https://tailscale.com/docs/account/manage-plans/free-plans-discounts).

## Mac

Сервис и Tailscale работают как два агента входа в систему: они стартуют после входа в macOS и перезапускаются при падении. Код агентов — [`reed-server.sh`](reed-server.sh), логи — `~/Library/Logs/REED/`.

```sh
server/reed-server.sh on       # установить и запустить оба агента
server/reed-server.sh status   # состояние агентов, адрес Funnel и проверка /health с токеном
server/reed-server.sh off      # остановить и удалить агентов
```

`tailscaled` работает без системного VPN-интерфейса (`--tun=userspace-networking`) и хранит вход, настройку Funnel и TLS-сертификат в `~/Library/Application Support/REED/Tailscale`. Сервис слушает только `127.0.0.1:8765` и при каждом старте берёт токен из Keychain. После перезапуска `tailscaled` TLS поднимается примерно за минуту.

### Первая настройка

Эти шаги нужны один раз на новом Mac. Установить CLI-вариант Tailscale и сохранить случайный токен в Keychain:

```sh
brew install tailscale
security add-generic-password -s local.reed.mac-service -a reed -w "$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
server/reed-server.sh on
```

Войти в tailnet по ссылке, которую напечатает первая команда, затем опубликовать только порт сервиса:

```sh
tailscale --socket=/private/tmp/reed-tailscaled.sock up --accept-dns=false --accept-routes=false
tailscale --socket=/private/tmp/reed-tailscaled.sock funnel --bg 8765
```

Первое включение Funnel открывает страницу Tailscale для разрешения публичного доступа, и TLS несколько минут обрывается, пока выписывается сертификат. Остановить публикацию: `tailscale --socket=/private/tmp/reed-tailscaled.sock funnel --https=443 off`. Не публиковать каталог файлов или другие локальные порты.

## iPhone/iPad

В REED открыть `Library → Mac connection`, вставить полный HTTPS-адрес из `funnel status` и токен из Keychain. На Mac токен можно скопировать без вывода в терминал: `security find-generic-password -s local.reed.mac-service -a reed -w | pbcopy`. `Save and check connection` должен показать `Connected`; затем добавить обычную статью по ссылке. Повторить проверку с включённым и выключенным VPN на телефоне. Готовая библиотека остаётся доступной без Mac. Передача исходного PDF с телефона сейчас не реализована.

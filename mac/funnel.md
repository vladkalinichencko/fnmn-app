# Пробное подключение FNMN через Tailscale Funnel

Funnel на бесплатном Tailscale Personal публикует локальный сервис Mac по HTTPS-адресу `*.ts.net`. Адрес доступен любому в интернете, поэтому FNMN требует отдельный bearer-токен на `/health` и `/articles`. Трафик Funnel имеет ограничение полосы. Mac должен оставаться включённым и подключённым к интернету. [Условия Funnel](https://tailscale.com/docs/features/tailscale-funnel), [бесплатный Personal](https://tailscale.com/docs/account/manage-plans/free-plans-discounts).

## Mac

Установить CLI-вариант и в первом терминале запустить его без системного VPN-интерфейса:

```sh
brew install tailscale
install -d -m 700 "$HOME/Library/Application Support/FNMN/Tailscale"
tailscaled --tun=userspace-networking --statedir="$HOME/Library/Application Support/FNMN/Tailscale" --socket=/private/tmp/fnmn-tailscaled.sock --no-logs-no-support
```

Во втором терминале войти в Tailscale по ссылке, которую напечатает команда:

```sh
tailscale --socket=/private/tmp/fnmn-tailscaled.sock up --accept-dns=false --accept-routes=false
```

Один раз сохранить случайный токен в Keychain. Из каталога `mac/` запустить сервис с этим токеном; команда не печатает его в терминале:

```sh
security add-generic-password -s local.fnmn.mac-service -a fnmn -w "$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
FNMN_TOKEN="$(security find-generic-password -s local.fnmn.mac-service -a fnmn -w)" ../.venv/bin/python -m uvicorn fnmn_service:app --host 127.0.0.1 --port 8765
```

После входа и запуска сервиса опубликовать только локальный HTTP-порт и прочитать выданный адрес:

```sh
tailscale --socket=/private/tmp/fnmn-tailscaled.sock funnel --bg 8765
tailscale --socket=/private/tmp/fnmn-tailscaled.sock funnel status
```

Первое включение Funnel может открыть страницу Tailscale для разрешения публичного доступа. Сразу после включения TLS несколько минут обрывается, пока Tailscale выписывает сертификат; проверять `/health` лучше после этого. Каталог состояния хранит вход и TLS-сертификат между запусками `tailscaled`. Остановить публикацию: `tailscale --socket=/private/tmp/fnmn-tailscaled.sock funnel --https=443 off`. Не публиковать каталог файлов или другие локальные порты.

## iPhone/iPad

В FNMN открыть `Library → Mac connection`, вставить полный HTTPS-адрес из `funnel status` и токен из Keychain. На Mac токен можно скопировать без вывода в терминал: `security find-generic-password -s local.fnmn.mac-service -a fnmn -w | pbcopy`. `Save and check connection` должен показать `Connected`; затем добавить обычную статью по ссылке. Повторить проверку с включённым и выключенным VPN на телефоне. Готовая библиотека остаётся доступной без Mac. Передача исходного PDF с телефона сейчас не реализована.

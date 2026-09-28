# Пробное подключение FNMN через Tailscale Funnel

Funnel на бесплатном Tailscale Personal публикует локальный сервис Mac по HTTPS-адресу `*.ts.net`. Адрес доступен любому в интернете, поэтому FNMN требует отдельный bearer-токен на `/health` и `/articles`. Трафик Funnel имеет ограничение полосы. Mac должен оставаться включённым и подключённым к интернету. [Условия Funnel](https://tailscale.com/docs/features/tailscale-funnel), [бесплатный Personal](https://tailscale.com/docs/account/manage-plans/free-plans-discounts).

## Mac

Установить CLI-вариант и в первом терминале запустить его без системного VPN-интерфейса:

```sh
brew install tailscale
tailscaled --tun=userspace-networking --state=mem: --socket=/private/tmp/fnmn-tailscaled.sock --no-logs-no-support
```

Во втором терминале войти в Tailscale по ссылке, которую напечатает команда:

```sh
tailscale --socket=/private/tmp/fnmn-tailscaled.sock up --accept-dns=false --accept-routes=false
```

Создать длинный случайный токен командой `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`. В третьем терминале из каталога `mac/` ввести тот же токен без записи в историю команд и запустить сервис:

```sh
read -rs 'FNMN_TOKEN?Mac service token: '
echo
export FNMN_TOKEN
python3 -m uvicorn fnmn_service:app --host 127.0.0.1 --port 8765
```

После входа и запуска сервиса опубликовать только локальный HTTP-порт и прочитать выданный адрес:

```sh
tailscale --socket=/private/tmp/fnmn-tailscaled.sock funnel --bg 8765
tailscale --socket=/private/tmp/fnmn-tailscaled.sock funnel status
```

Первое включение Funnel может открыть страницу Tailscale для разрешения публичного доступа. Команда `--state=mem:` хранит вход только до остановки `tailscaled`; это пробный режим. Остановить публикацию: `tailscale --socket=/private/tmp/fnmn-tailscaled.sock funnel --https=443 off`. Не публиковать каталог файлов или другие локальные порты.

## iPhone/iPad

В FNMN открыть `Library → Mac connection`, вставить полный HTTPS-адрес из `funnel status` и тот же токен. `Save and check connection` должен показать `Connected`; затем добавить обычную статью по ссылке. Повторить проверку с включённым и выключенным VPN на телефоне. Готовая библиотека остаётся доступной без Mac. Передача исходного PDF с телефона сейчас не реализована.

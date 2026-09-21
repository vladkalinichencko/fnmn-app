# VPS relay for the Mac processing service

Проверено 20 сентября 2026 года по официальной документации OpenSSH, nginx и Cloudflare. Цель — оставить обработку статей, PDF и транскрипций на Mac, а дать iOS/iPadOS-клиенту постоянный адрес через уже оплаченный VPS.

## Рекомендованная схема

```text
iPhone/iPad
    │ HTTPS + токен приложения
    ▼
VPS: публичный адрес, nginx, firewall
    │ 127.0.0.1:18080 на VPS
    ▼
SSH reverse forward, который держит Mac
    │ зашифрованный SSH-канал
    ▼
Mac: 127.0.0.1:8080, REST-сервис и все исходные/обработанные файлы
```

Mac сам открывает исходящее SSH-соединение к VPS с `RemoteForward`, например `127.0.0.1:18080` на VPS к `127.0.0.1:8080` на Mac. OpenSSH описывает `RemoteForward` именно как порт на удалённом сервере, соединённый через защищённый канал с локальной машиной. По умолчанию удалённый порт слушает только loopback, поэтому наружу его лучше не выставлять: nginx на VPS принимает HTTPS и проксирует запросы во внутренний порт SSH. [OpenSSH `ssh(1)`](https://man.openbsd.org/ssh), [OpenSSH `ssh_config(5)`, `RemoteForward`](https://man.openbsd.org/ssh_config#RemoteForward).

Минимальная форма соединения выглядит так:

```sh
ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -R 127.0.0.1:18080:127.0.0.1:8080 relay@vps.example
```

`ExitOnForwardFailure` заставляет SSH завершиться, если порт не удалось создать, а `ServerAliveInterval` и `ServerAliveCountMax` обнаруживают зависшее соединение. Автоматический повтор после обрыва нужен отдельному процессу-супервизору на Mac, например LaunchAgent с коротким циклом перезапуска. Эти параметры не делают Mac доступным во время сна: они только восстанавливают соединение после того, как Mac снова может выполнять процесс. [OpenSSH `ssh_config(5)`](https://man.openbsd.org/ssh_config#ExitOnForwardFailure), [keepalive-параметры](https://man.openbsd.org/ssh_config#ServerAliveInterval).

На VPS nginx должен слушать `443` и проксировать только нужный API-маршрут на `http://127.0.0.1:18080`. Для загрузки PDF или аудио нужно задать явный `client_max_body_size`; значение по умолчанию nginx — `1m`, а превышение даёт `413`. Для передачи больших тел без ожидания полной загрузки на VPS нужен `proxy_request_buffering off`; nginx тогда отправляет тело Mac по мере его получения. Ответы с большими файлами также можно отдавать без буферизации через `proxy_buffering off`. [nginx `client_max_body_size`](https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size), [nginx `proxy_request_buffering`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_request_buffering), [nginx `proxy_buffering`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering).

## Аутентификация

SSH-ключ Mac→VPS подтверждает право Mac держать forwarding, но не аутентифицирует приложение. Публичный API на VPS должен отдельно проверять токен приложения или клиентский сертификат. Минимальный MVP — HTTPS на VPS, длинный случайный bearer-токен в заголовке `Authorization`, ограничение маршрутов nginx и rate limit; токен нужно хранить в Keychain на iOS и не принимать в query string. В этой схеме VPS завершает TLS и видит содержимое запросов. Если VPS не должен видеть PDF и текст, следующий этап — TLS от приложения до сервиса на Mac, а VPS использовать как TCP-передатчик без расшифровки.

Если forwarding когда-нибудь выставлять напрямую на публичный адрес, `sshd` потребует подходящее значение `GatewayPorts`. OpenSSH предупреждает, что по умолчанию remote forwarding привязан к loopback и другие хосты не могут к нему подключиться. Поэтому nginx перед внутренним forwarding-портом безопаснее, чем включение wildcard-listen для SSH. [OpenSSH `sshd_config(5)`, `GatewayPorts`](https://man.openbsd.org/sshd_config#GatewayPorts).

## Поведение при сне и недоступности Mac

VPS сохраняет постоянный адрес, но не превращается в очередь задач. Когда Mac спит, выключен, потерял сеть или REST-сервис остановлен, SSH-канал отсутствует или не может обработать запрос. Клиент должен получать `503 Service Unavailable` или отдельный статус `processor_offline`, а не ждать бесконечно. Уже начатая передача оборвётся, если пропадёт Mac или SSH-канал.

Для повторяемого импорта приложение должно сначала отправить маленький запрос состояния, затем загрузить файл с таймаутом и повторить операцию по стабильному `job_id`. Сам файл и прогресс лучше сохранять на Mac, потому что VPS по этой схеме только передаёт поток. Если понадобится принимать импорт, пока Mac спит, это уже другая функция: VPS должен временно хранить файл и очередь, а Mac — забирать задания после пробуждения. Это увеличит объём серверного кода и поменяет границы хранения данных.

## Cloudflare Tunnel в этой схеме

Cloudflare Quick Tunnel не решает постоянный адрес: `cloudflared tunnel --url ...` создаёт случайный `trycloudflare.com`-адрес, не гарантирует uptime, ограничивает 200 одновременных запросов и не поддерживает SSE. Cloudflare прямо предназначает Quick Tunnels для тестов. [Cloudflare Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/).

Именованный Cloudflare Tunnel может дать стабильный hostname, но для публикации приложения Cloudflare требует аккаунт и домен, подключённый к Cloudflare. Его можно запускать на Mac напрямую, и тогда VPS не нужен; либо запускать на VPS, но тогда VPS должен иметь сетевой путь к Mac, например тот же SSH/VPN relay. При уже имеющемся публичном VPS это добавляет Cloudflare-зависимость без необходимости. [Cloudflare setup prerequisites](https://developers.cloudflare.com/tunnel/get-started/), [Cloudflare published applications](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/).

## HTTPS без покупки домена

Прямой `https://<статический-IP VPS>` теперь является рабочим вариантом. Let’s Encrypt с января 2026 года выдаёт публично доверенные IP-сертификаты для IPv4 и IPv6, но только через профиль `shortlived`: сертификат действует около шести дней и требует полностью автоматического обновления. Для проверки контроля IP используются `http-01` или `tls-alpn-01`, а не DNS challenge. Certbot поддерживает этот режим начиная с версии 5.4. [Let’s Encrypt: общая доступность IP-сертификатов](https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability), [профили Let’s Encrypt](https://letsencrypt.org/docs/profiles/), [Certbot для IP-сертификатов](https://letsencrypt.org/2026/03/11/shorter-certs-certbot).

Это подходит для iOS/iPadOS, если nginx отдаёт сертификат, содержащий именно этот IP, и соблюдает требования ATS. Apple требует HTTPS, доверенную цепочку, совпадение имени сервера с сертификатом, TLS 1.2 или новее и современные шифры. Самоподписанный сертификат или обычный HTTP для публичного VPS не являются планом для `URLSession`: придётся ослаблять доверие или устанавливать собственный корень на устройство. [Apple: предотвращение небезопасных соединений](https://developer.apple.com/documentation/security/preventing-insecure-network-connections).

Практический минус IP-сертификата — обновление каждые шесть дней становится частью эксплуатации VPS. Если Certbot или ACME-клиент перестанет обновлять сертификат, приложение внезапно начнёт получать TLS-ошибки, поэтому этот путь нужно сначала проверить на реальном VPS и контролировать срок сертификата. Он не требует платы за домен, но не является «настроил один раз и забыл».

Существующий hostname VPN можно использовать для API только если пользователь контролирует DNS-зону этого hostname. Тогда отдельный `api.<ваш-домен>` с отдельным сертификатом безопаснее, чем смешивать API и VPN на одном имени. Если VPN-адрес выдан провайдером и пользователь не может добавить DNS-запись или получить сертификат для поддомена, его нельзя надёжно переиспользовать как API subdomain. Конкретное состояние VPN hostname в текущих материалах не подтверждено, поэтому остаётся проверить: это собственный домен с управляемой DNS-зоной или чужой hostname сервиса.

Для FNMN без покупки домена остаются два реалистичных варианта: стабильный VPS IP с автоматически обновляемым Let’s Encrypt IP-сертификатом, либо VPN hostname только после подтверждения контроля над его DNS. Первый вариант проще по адресации, но требует строгой автоматизации шестидневной ротации; второй удобнее, если домен уже принадлежит пользователю.

## Решение для плана FNMN

Добавить транспортный слой как отдельный этап после локального REST-сервиса:

1. Mac-сервис слушает только `127.0.0.1` и хранит все исходные и обработанные данные локально.
2. Mac запускает reverse SSH forwarding на фиксированный loopback-порт VPS с SSH-ключом, ограниченным forwarding без shell-доступа.
3. VPS публикует один постоянный HTTPS base URL через nginx и проксирует `/api/*` на forwarding-порт.
4. iOS-клиент хранит один base URL и токен в Keychain, проверяет health/status и показывает Mac offline отдельно.
5. Для крупных файлов задаются лимиты, таймауты и потоковая передача; сервер не копирует PDF в постоянное хранилище VPS.

Это удовлетворяет условию «без нового платного сервиса» и сохраняет алгоритмы и данные на Mac. Постоянный адрес принадлежит VPS, а доступность обработки зависит от того, включён ли Mac и не спит ли он.

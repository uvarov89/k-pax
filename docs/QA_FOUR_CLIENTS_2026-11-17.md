# QA: четыре продукта K-Pax и X-Plm (17.11.2026)

База: main v1.0.65. Главный приоритет: клиенты Happ, INCY, v2rayN и Hiddify работают на тех же узлах, фирменные — нет. **Запуск движка ≠ реальный доступ через VPN.**

## Общий эталон и критерий PASS

Для одного и того же TEST-пользователя, узла, порта, протокола, SNI, ALPN, Reality/transport, сети и времени сравнить фирменный и работающий клиент. Проверить: запустился ли native TUN; DNS-resolve; HTTPS/TCP, UDP и Telegram; внешний IP должен быть адресом EXIT, а не провайдера; DNS, IPv4/IPv6 leaks, 1/5/20 минут. Конфиги сравнивать обезличенными: без UUID, паролей, токенов. Фиксировать точную сеть, модель, версию Android/Windows, теги release, SHA сборки и причину ошибки. Признаки: PASS, FAIL, BLOCKED (нет устройства, подписки, ключа), NOT RUN. Запуск flutter test/сборки — только CI PASS, не E2E PASS.

## A. K-Pax Android / space.kpax.app / kpaxDirect

**P0:** Android 12–16, реальный Android 16 (Wi-Fi + 5G); установка с исходной подписью, разрешения VPN и install packages, вход email/Telegram, проверка срока подписки, получение DE/FI/BG нод. По отдельности VLESS+REALITY, TLS/gRPC, WS/CDN, Hysteria2, TUIC, SS; один и тот же EXIT в Hiddify/Happ. Снимок VpnService Builder (адреса, маршруты, DNS, package list), libbox logs, protect(fd), underlying network; Green Connected только после DNS/HTTPS + подтверждения EXIT. Сценарии: ручной/авто сервер, неверные параметры Reality, недоступный сервер, failover, Wi-Fi↔5G, авиарежим, Doze, split tunnel, IPv6-only/NAT64, captive portal, blocked UDP/53, DNS leaks.

**P1:** 10 reconnect/stop/start подряд, отсутствие залипания foreground service, вход и восстановление после переустановки, expiry/403, профиль и устройства, 20-минутный трафик, автообновление 1.0.64/65 → signed APK (тот же сертификат/versionCode), ручной браузерный fallback без удаления приложения.

## B. X-Plm Android / online.xplm.app / xplmDirect

**P0:** всё из A, но email-only, x-plm.online, sub.x-plm.online, ссылки xplm://, своя API-панель и подпись X-Plm APK. Один и тот же тестовый узел сравнить с INCY и Hiddify. Убедиться, что чужой K-Pax URL/token/APK отвергается; FileProvider authority online.xplm.app.cache, install package-name и подписанный upgrade. Test Android 16, 5G и Wi-Fi; отдельно проверять тему/навигацию/серверный список.

**P1:** login/logout/renewal, 10 reconnect, split tunnel, 20-минутный трафик; Play flavour запрещает sideload.

## C. K-Pax Windows / KPax.exe + sing-box.exe + wintun.dll

**P0:** Windows 10/11 x64, обычная учётная запись, UAC, установка и обновление поверх 1.0.65, новый Wintun, права запуска/маршруты, DNS, выходной IP, TLS/HTTP, Telegram, UDP/QUIC, browser/v2rayN parity по тому же профилю. Эксперименты: запуск с админ-правами и без, старые firewall rules, конфликт VPN/TUN адаптеров, split tunnel selected process, IPv4/IPv6, kill switch (сейчас НЕ реализован в безопасном fail-closed виде), pid/config cleanup, process crashes, sleep/wake, Ethernet↔Wi-Fi.

**P1:** login email/Telegram, startup/tray/single instance, 10 reconnect, 20-минутный трафик, оба файла движка присутствуют в Inno installer, обновление version JSON + Inno, запрет downgrade.

## D. X-Plm Windows / XPlm.exe

**P0:** всё из C с APP_BRAND=xplm + BRAND=xplm, собственным AppId и X-Plm-Setup.exe, email-only, отдельными local config/pid и x-plm.online. Проверить, что DNS/Clash/процесс/настройки и ссылки не пересекаются с K-Pax, а два бренда могут быть установлены одновременно. Same-node Hiddify/v2rayN parity. Explicit no false Connected, no kill-switch security claim.

**P1:** UI/навигатор parity с X-Plm Android, перезапуск/обновление из-под непривилегированного пользователя, 10 reconnect и сон, deep-link xplm://.

## Автоматические гейты

1. На Linux и Windows запустить ВСЕ Dart unit/widget tests (не только selected smoke tests), фиксируя зависания и skip; отдельно flutter analyze и проверка форматирования без автоформатирования кодовой базы.
2. Android: сборки kpaxDirect + xplmDirect и kpaxPlay + xplmPlay, компиляция Kotlin+Gradle, merged manifest + package identities; APK signing/upgrade тестируется только с оригинальным ключом.
3. Windows: обе релизные сборки; наличие EXE, Wintun и sing-box; сборка Inno. Реальный сетевой E2E — только на disposable Windows VM/физическом устройстве.
4. Профили REALITY, VLESS/gRPC, WS, Hysteria2, TUIC, Shadowsocks с фальшивыми секретами; native sing-box check на 1.12.12 и 1.13.21; тестировать DNS automatic/manual, IPv6 policy.
5. Контракт с обеими панелями: login/start/status, подписка + метаданные, обработка 403/timeout, version/update URL, APK/installer подпись, DNS и CDN.
6. Никаких токенов, подлинных подписок, приватных ключей или паролей в CI, логах и issue.

## Выпуск

Не объявлять готовность до 100% P0 PASS на 4 сборках; внешнего IP = EXIT; отсутствия DNS/IP leaks; восстановления сети после обрыва; подписанных APK, инсталляторов Windows, корректного server update JSON и rollback. Все BLOCKED E2E фиксировать отдельно; не приравнивать их к PASS.

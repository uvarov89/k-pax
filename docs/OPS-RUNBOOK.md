# K-Pax — операционный runbook (сохранить)

Документ для людей и агентов Cursor. **Не кладите сюда пароли, `.p8`, содержимое приватных ключей, Platega secret, bot token.** Храните секреты отдельно (менеджер паролей / сейф); здесь — *где они лежат* и *как ими пользоваться*.

Связанные доки: [ios-apple-setup.md](ios-apple-setup.md), [ios-codemagic.md](ios-codemagic.md), [ios-testflight-qa.md](ios-testflight-qa.md).

---

## 1. Продукт и репозитории

| Что | Значение |
|-----|----------|
| Бренд | **K-Pax** |
| Сайт | https://k-pax.space |
| Подписка (host) | https://sub.k-pax.space/s/`<token>` |
| Flutter package name | `pulse_vpn` |
| Локальный репо | `C:\GitHub\antirkn_vpn` |
| GitHub (релизы APK/EXE) | https://github.com/uvarov89/k-pax |
| Android / iOS / Windows app id | `space.kpax.app` |
| Текущая версия клиента (pubspec) | см. `pubspec.yaml` → `version` (напр. `1.0.23+25`) |
| Deep link scheme | `kpax://` (`confirmed`, `paid`, `sub`, query `url`/`contact`) |

**Контакты в продукте:** `support@k-pax.space`, `access@k-pax.space`, бот `@KPax_Space_bot`, канал `t.me/kpaxvpn`.

---

## 2. Серверы (SSH)

Файл на рабочей машине: `~/.ssh/config` (Windows: `C:\Users\uvaro\.ssh\config`).

```
Host kpax          → 77.221.154.107   # панель + Caddy (k-pax.space / sub)
Host kpax-de       → 31.77.116.51     # exit DE (IP сменён хостером 2026-11-06; старый 144.31.221.141 мёртв)
Host kpax-fi       → 144.31.169.6     # exit FI
Host kpax-bg       → 79.124.7.111     # exit BG
Host xplm          → 45.133.209.80    # бренд X-PLM (edge → панель K-Pax)
Host kpax-ru       → 195.133.45.167   # РФ-фронт 1 (RuVDS)
Host kpax-ru2      → 152.228.112.142  # РФ-фронт 2 (AdminVPS)
User root
IdentityFile ~/.ssh/k-pax_ed25519
IdentitiesOnly yes
```
Ключ панели → ноды: `/etc/k-pax/id_ed25519` (на kpax). `kpax-ru` / `kpax-ru2` с ноутбука могут быть недоступны по SSH (фильтр хостера); управление — с `kpax`.

Публичный ключ: `~/.ssh/k-pax_ed25519.pub`  
Known hosts: `~/.ssh/known_hosts`

Проверка: `ssh kpax 'hostname; systemctl is-active k-pax caddy'`

Hostname панели сейчас: `matchstaff.ptr.network` (IP `77.221.154.107`).

---

## 3. Панель на kpax (главный деплой)

| Параметр | Значение |
|----------|----------|
| Код | `/opt/k-pax/panel.py` |
| WorkingDirectory | `/opt/k-pax` |
| systemd unit | `k-pax.service` → `python3 /opt/k-pax/panel.py` |
| Слушает | `127.0.0.1:8787` |
| Caddy | reverse_proxy `k-pax.space` и `sub.k-pax.space` → `:8787` |
| Конфиг (секреты!) | `/etc/k-pax/config.json` |
| База | `/var/lib/k-pax/k-pax.db` |
| Локальная копия кода | `C:\GitHub\antirkn_vpn\server\panel.py` |
| Unit в репо | `server/k-pax.service` |
| Caddyfile в репо | `server/Caddyfile` |

На диске рядом с конфигом также: `/etc/k-pax/id_ed25519` (+ `.pub`) — ключ панели → ноды; `known_hosts`; `backup.pass`.

Типичные ключи `/etc/k-pax/config.json` (только имена): `nodes` (de/fi/bg + optional `ru` front), `admin_user` + password hash/salt, `platega_merchant_id` / `platega_secret`, `telegram_bot_token` / `telegram_chat_id` / `telegram_restore_token`, `ss_ws_secret`, `brands`, mail restore. **Бэкапить config + БД вместе.**

Ноды в конфиге: `de` → `31.77.116.51`, `fi` → `144.31.169.6`, `bg` → `79.124.7.111`.

РФ-фронты (whitelist fallback / spare при резе зарубежья, ноя 2026):

| id | Хостер | IP | Подписка (connect host) |
|----|--------|-----|-------------------------|
| `ru` | RuVDS | `195.133.45.167` | `media.nastolkashop.store` (`self_domain`) |
| `ru2` | AdminVPS | `152.228.112.142` | сам IP (без `self_domain`, отдельная spare-строка) |

Оба: `role: front`, SNI `media.nastolkashop.store`, `front_ports` de=2443 / fi=2444 / bg=2445 → Reality inbound на РФ, outbound Reality на EU. В подписке **не** отдельная страна: те же Германия/Финляндия/Болгария, non-443 — spare после прямого EU. На каждой машине: `sing-box` + камуфляж HTTPS на `:443` и handshake `:8446` (на `ru` — nginx+LE; на `ru2` — Caddy, TLS **1.2 only** по KB AdminVPS, сертификат скопирован с `ru`). Relay UUID / ключи: `/var/lib/k-pax-ru/reality.env`.

DNS Namecheap (`nastolkashop.store` → Advanced DNS): dual-A Host=`media` → `195.133.45.167` и `152.228.112.142`.  
Продление LE: certbot на `ru` (`media.nastolkashop.store`). Автосинк на `ru2`:
- deploy-hook на `ru`: `/etc/letsencrypt/renewal-hooks/deploy/sync-media-ru2.sh` → `/etc/ssl/media/` + `systemctl reload caddy`
- запасной таймер на панели: `kpax-sync-media-cert.timer` → `/usr/local/sbin/kpax-sync-media-cert.sh` (каждые 6ч)
Ручной прогон: `ssh kpax '/usr/local/sbin/kpax-sync-media-cert.sh'`.

Trial: `TRIAL_DAYS = 14`. Лимит устройств: `DEVICE_LIMIT = 2`.

Reality SNI/dest (первичный TCP :443): **только свои домены** (требование VPSPay с 05.11.2026). Поле ноды `reality_sni` в `/etc/k-pax/config.json` = `self_domain`. На ноде: `tls.server_name` = этот домен, `reality.handshake` = `127.0.0.1:8446` (nginx + LE, как self-steal). Self-steal (:2053) — тот же домен/handshake.

Пул (ноябрь 2026, own SNI): `de` → `files.nastolkashop.store`, `fi` → `static.nastolkashop.store`, `bg` → `img.nastolkashop.store`. Миграция primary: `tool/_migrate_primary_reality_own_sni.py` на ноде → `sing-box check` → `systemctl restart sing-box`; на панели `tool/_panel_set_reality_sni.py` + `systemctl restart k-pax`. Клиентам нужен refresh подписки.

CDN front (этап 2): `cdn_host` в `/etc/k-pax/config.json` (сейчас `cdn.k-pax.space`). Caddy: сайт `cdn.k-pax.space` только `/w/` и `/x/` на ноды; панель на CDN не отдаётся. DNS в Cloudflare: `cdn` Proxied; `de`/`fi`/`bg`/`mail` — DNS only. SSL: Cloudflare **Full** или **Full Strict** (после LE на origin). Caddy с `admin off` — конфиг только через `systemctl restart caddy`, не `reload`.

### Деплой panel.py (команды с Windows / PowerShell)

```powershell
$local = "C:\GitHub\antirkn_vpn\server\panel.py"
python -m py_compile $local
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
ssh kpax "cp -a /opt/k-pax/panel.py /opt/k-pax/panel.py.bak-$stamp"
scp $local "kpax:/opt/k-pax/panel.py"
ssh kpax "python3 -m py_compile /opt/k-pax/panel.py && systemctl restart k-pax && sleep 1 && systemctl is-active k-pax && curl -fsS http://127.0.0.1:8787/healthz"
```

Проверки после выкладки:

- `curl -fsS https://k-pax.space/healthz` → `ok`
- `curl -sS 'https://k-pax.space/app/devices?token=x' | head` → JSON
- `curl -fsS https://k-pax.space/pay/done | findstr kpax://paid`

Откат: `ssh kpax 'cp -a /opt/k-pax/panel.py.bak-STAMP /opt/k-pax/panel.py && systemctl restart k-pax'`

### Важные HTTP-пути приложения

| Path | Назначение |
|------|------------|
| `/app/login` POST | старт входа (почта / @ник) |
| `/app/login/status` | poll сессии |
| `/app/confirm?t=` | confirm из письма |
| `/app/devices?token=` | список онлайн-устройств |
| `/app/devices/kick` POST | отключить устройство |
| `/app/android`, `/app/windows` | JSON версии автообновления |
| `/pay`, `/pay/done` | оплата; done → `kpax://paid` |
| `/s/<token>` на sub | тело подписки |

---

## 4. Exit-ноды (DE / FI / BG)

- sing-box на нодах; панель пушит пользователей по SSH (`CFG["ssh_key"]` на сервере панели).
- Selfsteal / WS порты в Caddy панели: `/w/de|fi|bg/...` → `:10086` на нодах (см. `server/Caddyfile`).
- Агент лимита устройств: ноды бьют в `/internal/sessions` (Bearer `limit_secret`).
- После Cloudflare на `sub.k-pax.space` ноды **не** должны ходить через CF (иначе 403 / `alert down` «нет данных >90с»). В `/etc/k-pax/limit.json` на каждой exit-ноде:
  `"panel": "https://sub.k-pax.space/internal/sessions"`,
  `"panel_ip": "77.221.154.107"` — TCP на origin, TLS SNI/Host = `sub.k-pax.space`.
  Код: `server/k-pax-limit.py` → `/usr/local/sbin/k-pax-limit.py`. После правки: `systemctl restart k-pax-limit`. В логе `sessions N …`, не `tick failed`. `/etc/hosts` для этого больше не нужен.

Скрипты в репо: `server/k-pax-user.py`, `server/k-pax-limit.py`, `server/node-allowlist.py`, …

Ночной `node_maintenance` (~01:30 UTC): только remove expired + top-up fresh spares (без nightly re-push уже лежащих spare). `k-pax-user.py` идемпотентен (`ok` vs `ok changed`); реальный рестарт `sing-box`/`xray` только при `changed`. Между нодами пауза `MAINTENANCE_STAGGER_SEC` (60с), чтобы Auto мог уйти на живой exit. Ошибка **front** (ru/ru2) — warn, commit всё равно; ошибка DE/FI/BG — abort commit. Деплой user-скрипта: `scp server/k-pax-user.py` → каждая нода `/usr/local/sbin/k-pax-user.py` + `chmod 755` (и копия на панели `/opt/k-pax/k-pax-user.py`).

### X-Plm edge (xplm)

Сайт `x-plm.online` на `45.133.209.80` — Caddy reverse_proxy на **origin** панели `https://77.221.154.107` (SNI/Host `k-pax.space`) с заголовками `X-Plm-Edge` + `X-Edge-Host`. Секрет и `edge_ips: ["45.133.209.80"]` в `/etc/k-pax/config.json` → `brands.xplm`.  
**Не** проксировать на `https://k-pax.space` через Cloudflare: CF ломает edge-бренд, на x-plm отдаётся лендинг K-Pax. Локальная копия: `server/Caddyfile.x-plm`.

### Abuse-фильтры на exit-нодах

На DE/FI/BG в `sing-box` и `xray`: reject BitTorrent + TCP `25/465/587` (SMTP). Обычный веб/мессенджеры не режет; снижает жалобы хостеру. После правок: `sing-box check` / `xray run -test`, затем `systemctl restart sing-box xray`. Правило SMTP для xray также в `server/node-allowlist.py` (чтобы не затёрлось при обновлении allowlist).

### Внешний watch сайта (exit-ноды)

`k-pax-watch` стоит **на DE/FI/BG** (не на панели): раз в минуту проверяет `k-pax.space` / `sub` / X-Plm / почту снаружи и пишет в Telegram при 2 фейлах подряд. Установка с панели: `python3 /opt/k-pax/k-pax-watch-install.py` (флаг `--test` — пробное сообщение). Unit’ы: `k-pax-watch.timer` + `.service`; конфиг ноды `/etc/k-pax-watch.json`.

---

## 5. Клиент (Flutter)

| Платформа | VPN | Package / notes |
|-----------|-----|-----------------|
| Android | `flutter_singbox_vpn` + Libbox | `space.kpax.app`, FileProvider `space.kpax.app.cache` |
| Windows | `sing-box.exe` + wintun | mutex single-instance; tray `kpax/window` |
| iOS | Packet Tunnel + vendored `sing_box` | K-Pax: `space.kpax.app` + `.extension` + `group.space.kpax.app`. X-Plm: `online.xplm.app` + `.extension` + `group.online.xplm.app` |

Ключевые пути:

- `lib/core/services/singbox_vpn_service.dart` — выбор сервиса по ОС  
- `lib/core/services/ios_singbox_vpn_service.dart`  
- `lib/core/services/deep_link_service.dart`  
- `lib/core/services/network_auto_connect.dart`  
- `third_party/flutter_singbox_vpn`, `third_party/sing_box`  
- `ios/PacketTunnel/`, `ios/scripts/build_libbox.sh`, `apply_ios_brand.rb`, `setup_packet_tunnel.rb`  
- `codemagic.yaml` → **`ios-testflight`** (K-Pax) / **`ios-testflight-xplm`** (X-Plm), integration **`kpax`**

Автообновление: панель отдаёт версии в `/app/android` и `/app/windows` (константы `ANDROID_APP_*` / `WINDOWS_APP_*` / `XPLM_*` в `panel.py` — синхронизировать с GitHub Releases при релизе). X-Plm Windows: `$env:APP_BRAND='xplm'; flutter build windows --release --dart-define=BRAND=xplm` → `ISCC windows\installer\x-plm.iss` → релиз `v*-xplm-windows`.

Подпись Android: локальный `android/key.properties` + keystore (**не в git**).

Android flavors: `brand` × `channel` → `kpaxDirect` / `xplmDirect` (sideload), `kpaxPlay` / `xplmPlay` (Google Play AAB). Store: `docs/STORE-RELEASE-1.0.51.md`, сборка `scripts/build-store-android.ps1`.

---

## 6. Apple / Codemagic (iOS)

| Item | K-Pax | X-Plm |
|------|-------|-------|
| App ID | `space.kpax.app` | `online.xplm.app` |
| Extension ID | `space.kpax.app.extension` | `online.xplm.app.extension` |
| App Group | `group.space.kpax.app` | `group.online.xplm.app` |
| Workflow | `ios-testflight` | `ios-testflight-xplm` |
| Setup doc | `docs/ios-apple-setup.md` | `docs/ios-apple-setup-xplm.md` |

Общее: ASC API key name в Codemagic **`kpax`**; `LIBBOX_SINGBOX_TAG` default `v1.13.21` (не 1.12 — Swift уже на новом CommandServer API); репо Flutter GitHub `k-pax` / `antirkn_vpn`.

Секреты Apple (хранить отдельно):

- Apple ID / пароль / 2FA  
- ASC API Key `.p8` + **Key ID** + **Issuer ID**  
- Team ID  

Полный чеклист: `docs/ios-apple-setup.md` + `docs/ios-testflight-qa.md`.

---

## 7. Что обязательно бэкапить (чеклист сейфа)

1. **SSH:** `k-pax_ed25519` + `.pub` + `~/.ssh/config` + `known_hosts`  
2. **Панель:** `/etc/k-pax/config.json`, `/var/lib/k-pax/k-pax.db` (регулярно; на сервере есть `k-pax-backup.*`)  
3. **Android keystore** + `key.properties`  
4. **Apple:** `.p8`, Key ID, Issuer ID, Team ID  
5. **Codemagic** account / GitHub oauth  
6. **Platega / Telegram bot / SMTP** — из `config.json` или менеджера паролей  
7. **DNS** домены: `k-pax.space`, `sub.k-pax.space` (у какого регистратора)  
8. **GitHub** `uvarov89/k-pax` + этот рабочий репо `antirkn_vpn`  
9. Копия этого файла: `docs/OPS-RUNBOOK.md`

---

## 8. Быстрые команды агенту / себе

```text
Деплой панели: scp server/panel.py → kpax:/opt/k-pax/panel.py; systemctl restart k-pax; curl healthz
SSH alias: kpax | kpax-de | kpax-fi | kpax-bg | xplm
iOS K-Pax: space.kpax.app + .extension + group.space.kpax.app ; workflow ios-testflight
iOS X-Plm: online.xplm.app + .extension + group.online.xplm.app ; workflow ios-testflight-xplm
Codemagic integration: kpax
Deep links: kpax://… | xplm://confirmed | xplm://paid
```

При сомнениях сначала читай **этот файл**, потом `docs/ios-*.md`, потом код — не ищи пароли в agent-transcripts.

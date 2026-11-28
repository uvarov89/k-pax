# Hosting / DNS provider APIs (emergency)

Secrets are **not** stored in git. Create scoped tokens in GitHub Actions **production** environment secrets only. Never paste tokens into ChatGPT chat.

## Cloudflare (DNS)

| Item | Guidance |
|------|----------|
| Secrets | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID_KPAX` |
| Token scope | **Zone → DNS → Edit** on `k-pax.space` only. Never Global API Key. |
| Workflow | `dns-ops.yml` via `/kpax dns action=list name=pl.k-pax.space` + `CONFIRM: DNS` |
| Allowlisted names | `pl.k-pax.space`, `de.k-pax.space`, `fi.k-pax.space`, `cdn.k-pax.space`, apex/www |
| Reality tip | Exit/front A records **DNS-only** (`proxied=false`) |
| Phone fallback | Cloudflare mobile app → DNS |
| Status | Secrets **must be created by operator** if missing — workflow fails closed |

## RuVDS (RU front)

| Item | Guidance |
|------|----------|
| Docs | https://ruvds.com/api-docs/ (API v2) |
| Secrets | `RUVDS_API_TOKEN`, optional `RUVDS_SERVER_IDS` (`ru=12345`) |
| Workflow | `provider-ops.yml` — `/kpax provider provider=ruvds action=status` + `CONFIRM: PROVIDER` |
| Allowed actions | `status`, `balance`, `reboot` (numeric id or map) |
| Phone fallback | RuVDS mobile / console power cycle |

## AdminVPS (RU2)

| Item | Guidance |
|------|----------|
| API | No reliable public reboot contract documented for our use |
| Phone fallback | https://my.adminvps.ru → service → reboot |
| Actions | inventory note only until operator supplies a verified API token + path |

## VPSPay / EU (DE, FI, PL)

| Item | Guidance |
|------|----------|
| API | **None published** — Telegram management only |
| Phone fallback | [@VPSPay_bot](https://t.me/VPSPay_bot) → server reboot / status |
| Actions | Prefer `kpax-ci restart sing-box` when SSH works; bot for hard power |

## Namecheap (`nastolkashop.store`)

| Item | Guidance |
|------|----------|
| API | Optional; ClientIp allowlist friction |
| Phone fallback | Namecheap app → Advanced DNS (`media` / `files` / `static` / `img`) |

## Panel host provider

| Item | Guidance |
|------|----------|
| Brand | **NEEDS VERIFY** with operator |
| Phone fallback | Provider console hard reboot |

## Fallback when admin VPS or Actions unavailable

1. Phone: Cloudflare app (DNS), RuVDS/AdminVPS/VPSPay (power).  
2. Phone: GitHub mobile cannot run SSH wrappers without Actions — wait for Actions or use laptop.  
3. Keep latest backup artifact downloaded to phone/cloud storage periodically.

## Polish exit (do not mutate without confirm)

| Field | Value |
|-------|-------|
| Host | `2.26.225.213` |
| SNI | `pl.k-pax.space` |
| Front | `2445` / relay `28445` |

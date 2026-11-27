# Hosting / DNS provider APIs (emergency)

Secrets are **not** stored in git. Create scoped tokens in GitHub Actions secrets only. Never paste tokens into ChatGPT chat.

## Cloudflare (DNS) — primary automated path

| Item | Guidance |
|------|----------|
| Secret names | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID_KPAX` |
| Token scope | **Zone → DNS → Edit** on `k-pax.space` only. Never Global API Key. |
| Workflow | `.github/workflows/dns-ops.yml` (`production` + `CONFIRM: DNS`) |
| Allowlisted names | `pl.k-pax.space`, `de.k-pax.space`, `fi.k-pax.space`, `cdn.k-pax.space`, apex/www |
| Reality tip | Exit/front A records **DNS-only** (`proxied=false`) |
| Phone fallback | Cloudflare mobile app / dashboard → DNS |

Status: token presence **NEEDS VERIFY** per environment secrets.

## Namecheap (nastolkashop.store)

| Item | Guidance |
|------|----------|
| API | Optional Namecheap API (ClientIp allowlist) — usually unused |
| Phone fallback | Namecheap app/site → Advanced DNS for `media` / `files` / `static` / `img` |
| Scope for ChatGPT | Describe needed record change; operator confirms in UI |

## VPS providers

| Host role | Typical provider | API / actions | Phone fallback |
|-----------|------------------|---------------|----------------|
| Panel | **NEEDS VERIFY** brand | Status, hard reboot if API token scoped | Provider console reboot |
| DE / FI / PL | VPSPay / EU VPS family | Status + reboot if enabled | Ticket / console |
| RU | RuVDS | Panel API or console | App/console power cycle |
| RU2 | AdminVPS | Console | Console |
| X-Plm edge | **NEEDS VERIFY** | Console | Console |

**Do not** give ChatGPT unbounded hosting account passwords. Prefer:

1. `kpax-ci` via Actions for service restart.  
2. One-shot `provider-reboot` workflow (future) with Environment approval.  
3. Operator phone console for power only.

## Domains / certificates

| Domain | Where | Notes |
|--------|-------|-------|
| `k-pax.space` | Cloudflare + LE on panel/Caddy | diag shows expiry |
| `media.nastolkashop.store` | LE on `ru`, sync to `ru2` | `kpax-sync-media-cert` |
| `pl.k-pax.space` | CF A → PL | DNS-only required for Reality |

## Billing / renewal alerts

| Item | Status |
|------|--------|
| VPS payment due alerts | **PARTIAL** — rely on provider email + Telegram watch; no unified Actions notifier yet |
| Cert expiry | diag + LE timers; alert automation **NEEDS VERIFY** |
| Domain expiry | registrar email; no CI poll yet |

## Polish exit (do not mutate)

| Field | Value |
|-------|-------|
| Host | `2.26.225.213` |
| SNI / domain | `pl.k-pax.space` |
| Front port | `2445` |
| Relay | `28445` → PL:443 |

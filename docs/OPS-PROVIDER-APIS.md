# Hosting / DNS provider APIs (emergency)

Secrets are **not** stored in git. Create scoped tokens in GitHub Actions secrets only.

## Cloudflare (DNS)

| Item | Guidance |
|------|----------|
| Secret names | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID_KPAX` (optional zone for x-plm later) |
| Token scope | **Zone → DNS → Edit** on `k-pax.space` only. Never Global API Key. |
| Workflow | `.github/workflows/dns-ops.yml` (`production` approval + `CONFIRM: DNS` via Issues gateway) |
| Allowlisted names | `pl.k-pax.space`, `de.k-pax.space`, `fi.k-pax.space`, `cdn.k-pax.space`, apex/www |
| Reality tip | A records for exits/fronts should be **DNS-only** (`proxied=false`) |

## VPS providers (status / reboot)

Documented for operator inventory — wire tokens only when confirmed:

| Provider (typical for this fleet) | Useful API | Emergency actions |
|-----------------------------------|------------|-------------------|
| RuVDS / similar RU VPS | Panel API or provider console | Power cycle front hosts |
| VPSPay / EU VPS | Provider ticket / API if enabled | Status + hard reboot for DE/FI/PL |
| Panel host | SSH + `systemctl` via `kpax-ci` | Prefer CI wrappers over provider reboot |

**Acceptance:** ChatGPT must not receive raw API keys in chat. Store as Actions secrets; invoke only through `dns-ops` / future `provider-reboot` workflows with Environment approval.

## Polish exit (`pl`)

| Field | Value (non-secret) |
|-------|--------------------|
| Host | `2.26.225.213` |
| SNI / domain | `pl.k-pax.space` |
| Front port on RU | `2445` |
| Panel relay | `28445` → PL:443 |

Ensure Cloudflare A `pl.k-pax.space` → `2.26.225.213` DNS-only before expecting SoftProbe OK from clients.

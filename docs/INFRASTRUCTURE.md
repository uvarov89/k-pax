# K-Pax / X-Plm — infrastructure inventory

**Updated:** 2026-11-27  
**Evidence class:** items marked **CONFIRMED** were verified from live panel/`OPS-RUNBOOK` / prior Actions. Items marked **NEEDS VERIFY** require a fresh remote check.

Related: [HANDOFF-NEXT-AGENT.md](HANDOFF-NEXT-AGENT.md), [OPS-RUNBOOK.md](OPS-RUNBOOK.md), [OPS-PROVIDER-APIS.md](OPS-PROVIDER-APIS.md).

## Interaction diagram (logical)

```text
Clients (K-Pax / X-Plm)
    │  HTTPS API / sub / updater
    ▼
Cloudflare (k-pax.space DNS; cdn proxied) ──► Panel VPS (Caddy → k-pax :8787)
    │                                              │
    │                                              ├─ SQLite /etc+DB
    │                                              ├─ kpax-front-relay :28443-28445
    │                                              └─ SSH push users → nodes
    │
    ├─ RU / RU2 fronts (:2443 DE, :2444 FI, :2445 PL) ──Reality──► DE/FI/PL exits :443
    └─ Direct Reality to DE/FI/PL :443 (path-dependent from RF)

X-Plm edge (x-plm.online) ──reverse_proxy──► Panel origin (not via CF HTML)
```

## Hosts

| ID | IP | Hostname / DNS | Role | OS | Specs | Status | Remote mgmt |
|----|-----|----------------|------|-----|-------|--------|-------------|
| panel | `77.221.154.107` | `matchstaff.ptr.network`; `k-pax.space`, `sub.k-pax.space` | Admin panel, Caddy, relay, DB | Linux (Debian/Ubuntu family) **CONFIRMED** | **NEEDS VERIFY** (CPU/RAM) | active **CONFIRMED** | SSH root (ops laptop); `gha`→`kpax-ci` via Actions |
| de | `31.77.116.51` | `files.nastolkashop.store` | Exit Reality DE | Linux | **NEEDS VERIFY** | active SoftProbe OK **CONFIRMED** (2026-11-27) | SSH from panel; `gha`→`kpax-ci` |
| fi | `144.31.169.6` | `static.nastolkashop.store` | Exit Reality FI | Linux | **NEEDS VERIFY** | active SoftProbe OK **CONFIRMED** | same |
| pl | `2.26.225.213` | `pl.k-pax.space` | Exit Reality PL | Linux | **NEEDS VERIFY** | TCP/relay up; SoftProbe front-pl FAIL **CONFIRMED** — **do not change PL config until RCA** | same |
| bg | `79.124.7.111` | `img.nastolkashop.store` | Exit BG | Linux | **NEEDS VERIFY** | `enabled: false` **CONFIRMED** | SSH when enabled |
| ru | `195.133.45.167` | `media.nastolkashop.store` | RU front | Linux | **NEEDS VERIFY** | active **CONFIRMED** | Prefer jump from panel (hoster SSH filter) |
| ru2 | `152.228.112.142` | dual-A `media` | RU2 front | Linux | **NEEDS VERIFY** | active **CONFIRMED** | same |
| xplm | `45.133.209.80` | `x-plm.online` | Brand edge → panel | Linux | **NEEDS VERIFY** | active **CONFIRMED** (docs) | SSH `xplm` |

## Ports (typical)

| Component | Ports |
|-----------|-------|
| Panel Caddy | 80/443 → `k-pax` `127.0.0.1:8787` |
| Front Reality | 2443 (DE), 2444 (FI), 2445 (PL); camouflage 443 / handshake 8446 |
| Panel TCP relay | 28443→DE, 28444→FI, 28445→PL |
| Exit Reality | 443 (+ self-steal 2053 historically) |
| SSH | 22 |

## Key paths

| Host | Path | Purpose |
|------|------|---------|
| panel | `/opt/k-pax/panel.py` | Panel code |
| panel | `/etc/k-pax/config.json` | Nodes, secrets (**never dump**) |
| panel | `/var/lib/k-pax/k-pax.db` | Users/payments |
| panel | `/etc/k-pax/ci-e2e.env` | Dedicated CI-E2E probe env (0600) |
| panel | `/usr/local/lib/kpax-ci/` | Fixed CI wrappers (root-owned) |
| panel | `/var/backups/k-pax-ci/` | pre-deploy / pre-rollback trees |
| nodes | `/etc/sing-box/config.json` | Exit/front sing-box |
| ru | `/var/lib/k-pax-ru/reality.env` | Front Reality material |

## Domains / DNS / CDN

| Name | Provider | Notes |
|------|----------|-------|
| `k-pax.space` / `sub` / `cdn` | Cloudflare | CDN proxied; exits DNS-only |
| `pl.k-pax.space` | Cloudflare | Must be DNS-only → PL IP |
| `*.nastolkashop.store` | Namecheap DNS | Front/exit SNI pool |
| `x-plm.online` | **NEEDS VERIFY** registrar | Edge on xplm VPS |

Site marketing frontend: **separate** from this repo (**CONFIRMED** `AGENTS.md`).

## Payments / bots / panels

| Component | Notes |
|-----------|-------|
| Platega | Panel integration; secrets in `config.json` |
| Telegram bots | `@KPax_Space_bot`; watch alerts from exits |
| Admin panel | HTTP on panel behind Caddy; not public-admin without auth |
| DB | SQLite only on panel (**CONFIRMED**) |

## Providers (billing / API)

See [OPS-PROVIDER-APIS.md](OPS-PROVIDER-APIS.md). Scoped tokens only in GitHub secrets — never chat.

## Dependencies / boot order (panel)

1. Network + DNS  
2. Caddy  
3. `k-pax`  
4. `kpax-front-relay`  
5. Fronts/exits `sing-box` (independent, but users synced from panel)

## Remote control channels

1. **GitHub Actions** + Issues `/kpax` gateway (ChatGPT phone path)  
2. Operator SSH from laptop (Cursor) — not required for ChatGPT ops  
3. Provider console reboot (last resort)

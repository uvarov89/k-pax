# Ops commands (ChatGPT / GitHub Actions)

**Do not put secrets in Issues.** Dangerous commands need confirm tokens + GitHub Environment `production` approval on the phone. Prefer reading **Actions job logs** (inline) over downloading ZIP artifacts.

## Issues gateway

### Read-only (no Environment approval)

| Command | Workflow | Notes |
|---------|----------|-------|
| `/kpax health` | `health-check.yml` | Fleet TCP/HTTP |
| `/kpax diag [targets]` | `diagnostics.yml` | Host journals |
| `/kpax diagnose targets=pl` | `deep-diag.yml` | Deep RCA + SoftProbe + DNS root-cause hints |
| `/kpax dns-check targets=pl` | `deep-diag.yml` | Resolve probes + sing-box DNS summary |
| `/kpax logs targets=pl` | `deep-diag.yml` | Journals inline in Actions |
| `/kpax analytics` | `analytics.yml` | Anonymized counts |
| `/kpax e2e` | `vpn-e2e.yml` | SoftProbe + inline fail logs |
| `/kpax config-get kind=singbox targets=pl` | `config-ops.yml` | Sanitized dump **includes dns.servers** |

### Dangerous (CONFIRM + production approval)

| Command | Confirm | Workflow |
|---------|---------|----------|
| `/kpax config …` | `CONFIRM: CONFIGOPS` | patch / apply / rollback / deadman-drill |
| `/kpax backup` / `restore-drill` / `deploy` / `rollback` / `e2e-maintain` / `dns` / `provider` / `node-ops` | matching `CONFIRM:` | see prior rows |

## PL DNS failure — ChatGPT fix playbook (owner confirm required)

**Root cause (verified):** sing-box `dns.servers[dns-local].address = 127.0.0.1`, but on PL nothing listens on `127.0.0.1:53` (only systemd-resolved stub `127.0.0.53` / `127.0.0.54`). DE/FI have **unbound** on `127.0.0.1:53`, so the same sing-box DNS shape works there.

**Do not invent other fixes first.** Preferred allowlisted patch:

### 1) Diagnose (read-only)

```text
/kpax diagnose targets=pl
/kpax dns-check targets=pl
/kpax config-get kind=singbox targets=pl
```

### 2) Dry-run patch (no write)

```text
/kpax config action=patch kind=singbox targets=pl dry_run=true patch_set=set:dns.server.dns-local.address=1.1.1.1
CONFIRM: CONFIGOPS
```

Approve **production**. From Actions logs copy `PATCH_DIGEST=…`.

Known digest for the preferred one-field change (verify in dry-run logs anyway):

`dns.server.dns-local.address=1.1.1.1` → `PATCH_DIGEST=918015c41ec439a04e1ac2a00663574ae6bae38b3085b70bd02e857a4707699a`

Alternative stub address (uses systemd-resolved):  
`patch_set=set:dns.server.dns-local.address=127.0.0.53`

### 3) Real apply (owner-bound digest + deadman + e2e)

```text
/kpax config action=patch kind=singbox targets=pl dry_run=false deadman=5 run_e2e=true patch_set=set:dns.server.dns-local.address=1.1.1.1 patch_digest=918015c41ec439a04e1ac2a00663574ae6bae38b3085b70bd02e857a4707699a
CONFIRM: CONFIGOPS
```

Effects on VPS: validate `sing-box check` → backup `/var/backups/k-pax-ci/config-singbox-pre-*` → atomic install → restart `sing-box` → arm deadman 5m → SoftProbe with egress IP.

### 4) If SoftProbe still bad / SSH lost

- Wait for deadman auto-restore, or  
- `/kpax config action=rollback kind=singbox targets=pl` + `CONFIRM: CONFIGOPS`  
- Cancel false deadman only after verified OK: `action=deadman-cancel`

### Optional: system resolver drop-in (usually not needed if sing-box points to 1.1.1.1)

```text
/kpax config action=patch kind=resolved-dropin targets=pl dry_run=true patch_set=set:DNS=1.1.1.1,8.8.8.8 set:FallbackDNS=9.9.9.9
CONFIRM: CONFIGOPS
```

Writes `/etc/systemd/resolved.conf.d/99-kpax-dns.conf`, restarts `systemd-resolved`, deadman-capable.

## Config-patch allowlist (DNS-related)

| kind | Fields |
|------|--------|
| `singbox` | `dns.server.<tag>.address`, `dns.add_server.<tag>`, `dns.final`, `dns.strategy`, plus prior inbound/outbound/log fields |
| `resolved-dropin` | `DNS`, `FallbackDNS`, `Domains`, `DNSStubListener`, `DNSOverTLS` |
| `ci-drill` | isolated drill file only |

Allowed DNS addresses: `1.1.1.1`, `1.0.0.1`, `8.8.8.8`, `8.8.4.4`, `9.9.9.9`, `149.112.112.112`, `208.67.222.222`, `208.67.220.220`, `127.0.0.1`, `127.0.0.53`, `127.0.0.54` (optional `udp://` + port).

**Live VPN kinds still require explicit owner agreement.** Isolated drills: `kind=ci-drill` / `deadman-drill`.

## Fixed remote binary (`kpax-ci`)

`gha` may only: `sudo /usr/local/lib/kpax-ci/kpax-ci <cmd>` (sudoers **not** widened).

| Subcommand | Effect |
|------------|--------|
| `diagnose` / `dns-check` / `logs` / `diag` / `health` / `e2e` | Read-oriented |
| `config-get` / `config-patch` / `config-diff` / `config-apply` / `config-rollback` | Allowlisted config |
| `deadman-*` | Local emergency rollback timer |
| `sync-users` | Fails if **any** node fails |

## Phone approval

GitHub mobile → pending Environment **production** → Approve → open **run URL** (logs inline).

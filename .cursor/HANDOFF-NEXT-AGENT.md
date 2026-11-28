# Handoff for next AI agent (K-Pax / X-Plm)

**Date:** 2026-11-28  
**Operator language:** Russian  
**Repo:** [uvarov89/k-pax](https://github.com/uvarov89/k-pax)  
**Site frontend:** not in this repo.

## Doc map

| Doc | Purpose |
|-----|---------|
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | Inventory + diagram |
| [OPS-COMMANDS.md](OPS-COMMANDS.md) | `/kpax` + `kpax-ci` |
| [DIAGNOSTICS.md](DIAGNOSTICS.md) | Outage order + E2E layers |
| [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) | Backup / rebuild / phone approve |
| [OPS-PROVIDER-APIS.md](OPS-PROVIDER-APIS.md) | Cloudflare / RuVDS / phone fallbacks |
| [KNOWN-ISSUES.md](KNOWN-ISSUES.md) | Open defects (PL / RU2) |
| [ACCEPTANCE-TESTS.md](ACCEPTANCE-TESTS.md) | VERIFIED matrix + run links |
| [OPS-RUNBOOK.md](OPS-RUNBOOK.md) | Human SSH detail |

## Access

| Access | You |
|--------|-----|
| GitHub code / Actions logs / Issues gateway | Yes |
| Direct SSH / Cursor laptop | Do not rely on it |
| Secrets in chat | **Never** |
| PL VPN config changes | **Forbidden** without operator confirm |
| Live VPN config apply (`singbox`/… ) | Only after explicit operator agree; prefer `ci-drill` first |
| Mutate workflows | Need `CONFIRM:` + phone Environment **production** approve |

## ChatGPT phone path

Read-only:

```text
/kpax health
/kpax diag panel,de,fi,pl,ru,ru2
/kpax analytics
/kpax e2e
/kpax config-get kind=singbox targets=panel,de,fi,pl,ru,ru2
```

Mutate (same message includes CONFIRM; then approve in GitHub mobile):

```text
/kpax backup
CONFIRM: BACKUP

/kpax restore-drill
CONFIRM: RESTOREDRILL

/kpax deploy paths=ci_marker.py
CONFIRM: DEPLOY

/kpax e2e-maintain
CONFIRM: E2EMAINTAIN

/kpax provider provider=inventory
CONFIRM: PROVIDER

/kpax dns action=list name=pl.k-pax.space
CONFIRM: DNS

/kpax config action=diff kind=ci-drill targets=panel
CONFIRM: CONFIGOPS

/kpax config action=apply kind=ci-drill targets=panel dry_run=true
CONFIRM: CONFIGOPS

/kpax config action=apply kind=ci-drill targets=panel dry_run=false deadman=5
CONFIRM: CONFIGOPS
```

**Config fix loop:** `config-get` → commit candidate in `ops/candidates/` → `diff` → `apply dry_run=true` → `apply dry_run=false` (+ deadman) → optional `run_e2e=true` → `rollback` / deadman if bad.

**Note:** `/kpax e2e` is SoftProbe-only. Refreshing `CI-E2E` / syncing UUID is `/kpax e2e-maintain`.

## Architecture short

Service bugs → `server/` / fronts / relay. Client bugs → `lib/`.  
`gha` sudo → **only** `/usr/local/lib/kpax-ci/kpax-ci` (never widen).

## Fleet

| ID | IP | Role |
|----|-----|------|
| panel | 77.221.154.107 | panel + relay + Caddy |
| de / fi / pl | 31.77.116.51 / 144.31.169.6 / 2.26.225.213 | exits (PL SoftProbe FAIL) |
| ru / ru2 | 195.133.45.167 / 152.228.112.142 | fronts (RU2 Reality flaky) |
| bg | 79.124.7.111 | disabled |
| xplm | 45.133.209.80 | brand edge |

## Operator secrets

| Secret | Purpose |
|--------|---------|
| `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ZONE_ID_KPAX` | DNS ops (operator: already connected) |
| `RUVDS_API_TOKEN` + optional `RUVDS_SERVER_IDS` | Optional; hardware reboot is manual |
| Already present | `KPAX_DEPLOY_*`, `KPAX_BACKUP_PASSPHRASE`, `KPAX_OPS_ALLOWLIST` |

## Immediate priorities

1. Keep PL config frozen until RCA + confirm.  
2. Use `kind=ci-drill` for config-ops acceptance; never apply live `singbox` without agree.  
3. Track acceptance links in ACCEPTANCE-TESTS.md.

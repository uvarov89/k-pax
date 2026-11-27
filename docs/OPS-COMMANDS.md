# Ops commands (ChatGPT / GitHub Actions)

**Do not put secrets in Issues.** Dangerous commands need confirm tokens + GitHub Environment `production` approval on the phone.

## Issues gateway

Post on an open Issue (authorized login in `KPAX_OPS_ALLOWLIST` or repo admin/maintain):

### Read-only

| Command | Dispatches | Notes |
|---------|------------|-------|
| `/kpax health` | `health-check.yml` | Fleet TCP/HTTP; fails on FAIL marks |
| `/kpax diag [panel,de,fi,pl,ru,ru2]` | `diagnostics.yml` | Host journals, resources, certs |
| `/kpax diagnostics …` | same | alias |
| `/kpax inventory` | `diagnostics.yml` (all listed) | inventory-style diag |
| `/kpax analytics` | `analytics.yml` | Anonymized counts |
| `/kpax e2e` | `vpn-e2e.yml` | SoftProbe + egress; PL affects status |

Bot replies with **concrete Actions run URL**. Duplicate identical command within 15 minutes is ignored.

### Dangerous (same message must include confirm line)

| Command | Confirm line | Workflow |
|---------|--------------|----------|
| `/kpax backup` | `CONFIRM: BACKUP` | `backup.yml` |
| `/kpax deploy paths=panel.py` | `CONFIRM: DEPLOY` | `deploy.yml` |
| `/kpax deploy paths=panel.py restart=true` | `CONFIRM: DEPLOY` | restart after install |
| `/kpax rollback` | `CONFIRM: ROLLBACK` | latest `pre-deploy-*` |
| `/kpax rollback backup=pre-deploy-YYYY…` | `CONFIRM: ROLLBACK` | named backup |
| `/kpax dns …` | `CONFIRM: DNS` | `dns-ops.yml` |
| `/kpax node-ops action=restart targets=pl service=sing-box` | `CONFIRM: NODEOPS` | `node-ops.yml` |

## Fixed remote binary (`kpax-ci`)

On each host, `gha` may only: `sudo /usr/local/lib/kpax-ci/kpax-ci <cmd>`.

| Subcommand | Effect |
|------------|--------|
| `diag [hours]` | Read-only host diagnostics |
| `health <panel\|front\|exit>` | Role health |
| `e2e` | SoftProbe suite (panel) |
| `ensure-e2e-env` | Upsert `CI-E2E` user + `/etc/k-pax/ci-e2e.env` |
| `validate-singbox` | `sing-box check` |
| `sync-users` | Panel user sync |
| `restart <k-pax\|kpax-front-relay\|sing-box\|caddy>` | Allowlisted restart |
| `backup` | Tar allowlisted paths → `/tmp/kpax-ci-backup-*.tar.gz` |
| `analytics [days]` | Anonymized DB stats |
| `list-backups` | `/var/backups/k-pax-ci` |
| `deploy-install <stamp> <file.py>…` | Install staged `/tmp/kpax-ci-stage` files |
| `rollback [name]` | Restore backup tree + restart `k-pax` |

## Workflow inputs (manual Run workflow)

Same as gateway; prefer Issues when ChatGPT lacks `workflow_dispatch` UI.

## Auth / safety

- Unauthorized `/kpax` → bot refuses.
- Production Environment required for mutate workflows.
- No arbitrary root shell; wrappers root-owned `go-w`.
- Never paste UUID / subscription URLs / SSH keys into chat.

# Ops commands (ChatGPT / GitHub Actions)

**Do not put secrets in Issues.** Dangerous commands need confirm tokens + GitHub Environment `production` approval on the phone.

## Issues gateway

### Read-only (no Environment approval)

| Command | Workflow | Notes |
|---------|----------|-------|
| `/kpax health` | `health-check.yml` | Fleet TCP/HTTP |
| `/kpax diag [targets]` | `diagnostics.yml` | Host journals |
| `/kpax analytics` | `analytics.yml` | Anonymized counts |
| `/kpax e2e` | `vpn-e2e.yml` | SoftProbe only — **no** ensure/sync |
| `/kpax config-get kind=singbox targets=panel,de` | `config-ops.yml` | Sanitized allowlisted config dump |

Kinds for get: `singbox` (Reality/routes summarized), `caddy`, `relay-unit`, `kpax-unit`, `panel-config` (secrets redacted), `ufw-status`, `ci-drill`.

### Dangerous (CONFIRM + production approval)

| Command | Confirm | Workflow |
|---------|---------|----------|
| `/kpax backup` | `CONFIRM: BACKUP` | Encrypted off-panel artifact + integrity |
| `/kpax restore-drill` | `CONFIRM: RESTOREDRILL` | Isolated decrypt/verify (no prod write) |
| `/kpax deploy paths=ci_marker.py` | `CONFIRM: DEPLOY` | `kpax-ci deploy-install` |
| `/kpax rollback` | `CONFIRM: ROLLBACK` | `kpax-ci rollback` |
| `/kpax e2e-maintain` | `CONFIRM: E2EMAINTAIN` | ensure-e2e-env + sync-users |
| `/kpax dns action=list name=pl.k-pax.space` | `CONFIRM: DNS` | Cloudflare allowlist |
| `/kpax provider provider=inventory` | `CONFIRM: PROVIDER` | Inventory / RuVDS |
| `/kpax node-ops action=restart targets=pl service=sing-box` | `CONFIRM: NODEOPS` | Fixed wrappers |
| `/kpax config action=diff\|apply\|rollback kind=… targets=…` | `CONFIRM: CONFIGOPS` | Allowlisted config ops |

### Config ops (ChatGPT remote fix path)

1. Diagnose with `/kpax health` / `diag` / `e2e` / `config-get`.
2. Commit candidate under `ops/candidates/` (see mapping below) — never paste secrets into Issues.
3. Preview: `/kpax config action=diff kind=ci-drill targets=panel` + `CONFIRM: CONFIGOPS` → approve.
4. Dry-run: `action=apply … dry_run=true`.
5. Apply: `action=apply … dry_run=false deadman=5` (+ optional `run_e2e=true`). Pre-apply backup + validate + atomic install + selective restart + deadman timer.
6. If SSH/path dies: local deadman restores last `config-<kind>-pre-*` backup.
7. Rollback: `action=rollback kind=…` or wait for deadman; cancel with `action=deadman-cancel`.

**Live VPN kinds** (`singbox`, `caddy`, `relay-unit`, …): only after explicit operator agreement. Isolated drills use `kind=ci-drill` → `/etc/k-pax/ci-drill.conf`.

Candidate files:

| kind | Repo path | Live path | Restart |
|------|-----------|-----------|---------|
| `singbox` | `ops/candidates/singbox.json` | `/etc/sing-box/config.json` | `sing-box` |
| `caddy` | `ops/candidates/caddy.Caddyfile` | `/etc/caddy/Caddyfile` | `caddy` |
| `relay-unit` | `ops/candidates/kpax-front-relay.service` | systemd unit | `kpax-front-relay` |
| `kpax-unit` | `ops/candidates/k-pax.service` | systemd unit | `k-pax` |
| `panel-config` | `ops/candidates/panel-config.json` | `/etc/k-pax/config.json` | `k-pax` |
| `ci-drill` | `ops/candidates/ci-drill.conf` | `/etc/k-pax/ci-drill.conf` | none |

Targets: `panel`, `de`, `fi`, `pl`, `ru`, `ru2`.

## Fixed remote binary (`kpax-ci`)

`gha` may only: `sudo /usr/local/lib/kpax-ci/kpax-ci <cmd>`.

| Subcommand | Effect |
|------------|--------|
| `diag` / `health` / `e2e` / `validate-singbox` / `analytics` | Read-oriented |
| `config-get` / `deadman-status` | Sanitized config / deadman state |
| `config-diff` / `config-apply` / `config-rollback` | Allowlisted mutate (via Actions) |
| `deadman-arm` / `deadman-cancel` / `deadman-fire` | Local emergency rollback timer |
| `ensure-e2e-env` / `sync-users` | Mutate test account / node users |
| `backup` | DR tarball under `/tmp` |
| `deploy-install` / `rollback` / `list-backups` | Panel code |
| `restart <svc>` | Allowlisted units only |

## Phone approval

GitHub mobile → pending Environment **production** → Approve → open run URL from bot comment.

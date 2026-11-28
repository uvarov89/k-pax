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

## Fixed remote binary (`kpax-ci`)

`gha` may only: `sudo /usr/local/lib/kpax-ci/kpax-ci <cmd>`.

| Subcommand | Effect |
|------------|--------|
| `diag` / `health` / `e2e` / `validate-singbox` / `analytics` | Read-oriented |
| `ensure-e2e-env` / `sync-users` | Mutate test account / node users |
| `backup` | DR tarball under `/tmp` |
| `deploy-install` / `rollback` / `list-backups` | Panel code |
| `restart <svc>` | Allowlisted units only |

## Phone approval

GitHub mobile → pending Environment **production** → Approve → open run URL from bot comment.

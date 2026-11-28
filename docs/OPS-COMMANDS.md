# Ops commands (ChatGPT / GitHub Actions)

**Do not put secrets in Issues.** Dangerous commands need confirm tokens + GitHub Environment `production` approval on the phone. Prefer reading **Actions job logs** (inline) over downloading ZIP artifacts.

## Issues gateway

### Read-only (no Environment approval)

| Command | Workflow | Notes |
|---------|----------|-------|
| `/kpax health` | `health-check.yml` | Fleet TCP/HTTP |
| `/kpax diag [targets]` | `diagnostics.yml` | Host journals |
| `/kpax diagnose targets=pl` | `deep-diag.yml` | Deep RCA: Reality PBK/SID/SNI fingerprints, CI-E2E UUID presence, hops, SoftProbe, inline redacted logs |
| `/kpax logs targets=pl` | `deep-diag.yml` | Same deep-diag with journals (Actions-visible) |
| `/kpax analytics` | `analytics.yml` | Anonymized counts |
| `/kpax e2e` | `vpn-e2e.yml` | SoftProbe + **inline** fail logs — **no** ensure/sync |
| `/kpax config-get kind=singbox targets=panel,de` | `config-ops.yml` | Sanitized allowlisted config dump |

### Dangerous (CONFIRM + production approval)

| Command | Confirm | Workflow |
|---------|---------|----------|
| `/kpax backup` | `CONFIRM: BACKUP` | Encrypted off-panel artifact |
| `/kpax restore-drill` | `CONFIRM: RESTOREDRILL` | Isolated decrypt/verify |
| `/kpax deploy paths=ci_marker.py` | `CONFIRM: DEPLOY` | Panel code install |
| `/kpax rollback` | `CONFIRM: ROLLBACK` | Panel code rollback |
| `/kpax e2e-maintain` | `CONFIRM: E2EMAINTAIN` | ensure-e2e-env + sync-users |
| `/kpax dns …` | `CONFIRM: DNS` | Cloudflare allowlist |
| `/kpax provider …` | `CONFIRM: PROVIDER` | Inventory / RuVDS |
| `/kpax node-ops …` | `CONFIRM: NODEOPS` | Fixed wrappers |
| `/kpax config …` | `CONFIRM: CONFIGOPS` | Config get-adjacent mutate |

### Config ops (in-place patch preferred)

Diagnose first (`/kpax diagnose targets=pl`). Then:

**A. In-place patch (no full config in GitHub)**

1. Dry-run:
```text
/kpax config action=patch kind=ci-drill targets=panel dry_run=true patch_set=set:note=probe
CONFIRM: CONFIGOPS
```
2. Note `PATCH_DIGEST=…` from Actions logs.
3. Real apply (digest binds confirmation to the exact change):
```text
/kpax config action=patch kind=ci-drill targets=panel dry_run=false deadman=5 patch_set=set:note=probe patch_digest=<sha256>
CONFIRM: CONFIGOPS
```
4. Optional `run_e2e=true` → SoftProbe + egress IP after apply.
5. SSH-loss safety: local deadman restores backup unless cancelled.
6. Rollback: `action=rollback` or wait for deadman.

Allowlisted patch fields:

| kind | Fields |
|------|--------|
| `singbox` | `log.level`, `inbound.<tag>.sni\|listen_port`, `outbound.<tag>.server\|server_port\|sni` |
| `panel-config` | `nodes.<id>.reality_sni\|self_domain\|enabled\|host` (never pbk/sid/keys) |
| `ci-drill` | arbitrary `key=value` lines under `/etc/k-pax/ci-drill.conf` |

**B. Full candidate apply** (only when needed): commit `ops/candidates/<kind>` then `action=diff|apply`.

**C. Deadman auto-fire proof (isolated):**
```text
/kpax config action=deadman-drill kind=ci-drill targets=panel
CONFIRM: CONFIGOPS
```

**Live VPN kinds** (`singbox`, …): only after explicit operator agreement. PL config frozen until RCA + confirm.

## Fixed remote binary (`kpax-ci`)

`gha` may only: `sudo /usr/local/lib/kpax-ci/kpax-ci <cmd>`.

| Subcommand | Effect |
|------------|--------|
| `diag` / `diagnose` / `logs` / `health` / `e2e` / `validate-singbox` / `analytics` | Read-oriented |
| `config-get` / `deadman-status` | Sanitized config / deadman state |
| `config-diff` / `config-apply` / `config-patch` / `config-rollback` | Allowlisted mutate |
| `deadman-arm` / `deadman-cancel` / `deadman-fire` | Local emergency rollback timer |
| `ensure-e2e-env` / `sync-users` | Test account / node users (`sync-users` fails if **any** node fails) |
| `backup` / `deploy-install` / `rollback` / `list-backups` / `restart` | DR / panel / units |

## Phone approval

GitHub mobile → pending Environment **production** → Approve → open **run URL** from bot comment (logs are inline).

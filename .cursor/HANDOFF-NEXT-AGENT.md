# Handoff for next AI agent (K-Pax / X-Plm)

**Date:** 2026-11-27  
**Operator language:** Russian  
**Repo:** [uvarov89/k-pax](https://github.com/uvarov89/k-pax) (Flutter client + `server/` control-plane source). Site frontend is **not** in this repo.  
**Also:** `docs/HANDOFF-NEXT-AGENT.md` (same content).

---

## 1. Your access

| Access | You |
|--------|-----|
| GitHub — read/change code | Yes |
| Branches + Pull Requests | Yes |
| **GitHub Actions** | **Yes** — Issues gateway **and** `workflow_dispatch` |
| Panel / node SSH as user `gha` | **Via Actions only** (fixed `/usr/local/lib/kpax-ci/kpax-ci`) |
| Direct laptop / Cursor SSH | No (Cursor may have host SSH; ChatGPT must not rely on it) |
| Subscriber PII / raw DB download | No (analytics anonymized; backup encrypted) |
| Publish store / TestFlight / GitHub Release | **Only after separate operator confirmation** |

**Do not ask for private keys in chat.** Secrets live in GitHub Actions (repo + `production` environment).

### ChatGPT without `workflow_dispatch`

GitHub connector cannot press **Run workflow**. Use an Issue (or comment) as an **authorized** user:

```text
/kpax health
/kpax diag panel,de,fi,pl,ru,ru2
/kpax analytics
/kpax e2e
```

Dangerous (same message must include confirm token; Environment `production` approval still required):

```text
/kpax backup
CONFIRM: BACKUP

/kpax deploy paths=panel.py
CONFIRM: DEPLOY

/kpax rollback
CONFIRM: ROLLBACK

/kpax dns
CONFIRM: DNS
```

Auth: secret `KPAX_OPS_ALLOWLIST` (comma logins) **or** repo `admin`/`maintain`. Workflow: `ops-gateway.yml`.

---

## 2. Architecture (short)

| Area | Path | Role |
|------|------|------|
| App UI / state | `lib/` | Flutter client — **do not thrash for RF path bugs** |
| Server panel | `server/panel.py` → live `/opt/k-pax/panel.py` | Subs, updater |
| CI remotes | `tools/ci/wrappers/` → `/usr/local/lib/kpax-ci/` | Fixed `kpax-ci` only |
| Workflows | `.github/workflows/` | Diagnostics, health, e2e, deploy… |

**Golden rule:** Service path bugs → `server/` / fronts / relay. Universal client bugs → `lib/`.

---

## 3. Servers and services

| ID | Host | Role | Notes |
|----|------|------|-------|
| panel | `77.221.154.107` | `k-pax`, `kpax-front-relay`, Caddy | `/opt/k-pax`, `/etc/k-pax`, DB `/var/lib/k-pax/k-pax.db` |
| de | `31.77.116.51` | exit Reality | SoftProbe via front **OK** |
| fi | `144.31.169.6` | exit Reality | SoftProbe via front **OK** |
| pl | `2.26.225.213` | exit Reality | **TCP/relay up; SoftProbe via front-pl:2445 currently FAIL** |
| ru / ru2 | fronts | 2443/2444/2445 | `pl` on **2445** |
| bg | `79.124.7.111` | exit | **`enabled: false`** |

Relay: `28443`→DE, `28444`→FI, `28445`→PL. CI user **`gha`** sudo → **only** `/usr/local/lib/kpax-ci/kpax-ci`.

E2E secrets file on panel (not in git): `/etc/k-pax/ci-e2e.env` (mode 0600).

---

## 4. App versions

| Channel | Version |
|---------|---------|
| Android (live updater) | **1.0.84** |
| Windows | **1.0.81** |
| Known-good rollback | **1.0.70** |

---

## 5. GitHub Actions

| Workflow | Trigger | Approval | Purpose |
|----------|---------|----------|---------|
| Ops gateway | Issue `/kpax …` | authz only | Dispatches other workflows |
| Health check | schedule `*/10` + manual + gateway | no | TCP/http; **job fails on FAIL**; Telegram/issue alert |
| Diagnostics | manual + gateway | no | Host journals (redacted) |
| VPN E2E | manual + gateway | no | Reality SoftProbe + egress IP (not TCP-only) |
| Analytics | manual + gateway | no | Anonymized counts |
| Node ops | manual (+ gateway hint) | **production** | diag/health/validate/sync/restart |
| Backup / Deploy / Rollback | manual + gateway | **production** | Encrypted backup; allowlisted deploy; restore |
| DNS ops | manual + gateway | **production** | Cloudflare allowlisted A records |

### Secrets

`KPAX_DEPLOY_SSH_KEY`, `KPAX_DEPLOY_SSH_KNOWN_HOSTS`, `KPAX_DEPLOY_HOST`, `KPAX_BACKUP_PASSPHRASE`, `KPAX_OPS_ALLOWLIST`, optional `KPAX_ALERT_TELEGRAM_*`, optional `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ZONE_ID_KPAX`, `ANDROID_*`.

### Fixed remote helpers

`tools/ci/wrappers/kpax-ci` → install via `tools/ci/bootstrap_wrappers_on_panel.sh` + `push_wrappers_to_nodes.py`.  
Commands: `diag`, `health <role>`, `e2e`, `validate-singbox`, `sync-users`, `restart <svc>`, `backup`, `analytics`, `list-backups`.

Provider notes: `docs/OPS-PROVIDER-APIS.md`.

---

## 6. Deploy / rollback order

1. `/kpax backup` + `CONFIRM: BACKUP` → approve `production` → Artifact.  
2. `/kpax deploy` + `CONFIRM: DEPLOY` → approve → prefer `restart=false` smoke first.  
3. `/kpax health` + `/kpax e2e`.  
4. Bad: `/kpax rollback` + `CONFIRM: ROLLBACK`.

Never delete user data. Never widen `gha` sudoers beyond `kpax-ci`.

---

## 7. Open issues

- **PL SoftProbe** (`front-pl:2445` / `to-pl` hop) returns non-204 while DE/FI fronts are 204. TCP `:443` and relay `28445` listen. Fix PL Reality/`pl.k-pax.space` DNS-only + outbound keys — **server**, not Flutter.
- BG offline.
- Cloudflare secrets optional until operator creates scoped token.

---

## 8. Verified runs

Update after each acceptance pass (replace with latest green links):

| Check | Link |
|-------|------|
| Diagnostics | https://github.com/uvarov89/k-pax/actions/runs/46009049713 |
| Health (green, fail-on-FAIL) | https://github.com/uvarov89/k-pax/actions/runs/46009456544 |
| Health (correctly red earlier) | https://github.com/uvarov89/k-pax/actions/runs/46009042924 |
| Analytics | https://github.com/uvarov89/k-pax/actions/runs/46009063235 |
| VPN E2E (green; PL advisory) | https://github.com/uvarov89/k-pax/actions/runs/46010045313 |
| Backup / Deploy smoke | https://github.com/uvarov89/k-pax/actions/runs/45988970897 · https://github.com/uvarov89/k-pax/actions/runs/45988979544 |

Historical: https://github.com/uvarov89/k-pax/actions/runs/45962067665 · https://github.com/uvarov89/k-pax/actions/runs/45962074072 · https://github.com/uvarov89/k-pax/actions/runs/45962079934

End of handoff.

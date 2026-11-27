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
| **GitHub Actions** (diagnostics / health / analytics / build) | **Yes** — `workflow_dispatch` |
| Panel / node SSH as user `gha` | **Via Actions only** (deploy key in secrets) |
| Direct laptop / Cursor SSH | No |
| Subscriber PII / raw DB download | No (analytics is anonymized) |
| Publish store / TestFlight / GitHub Release | **Only after separate operator confirmation** |

**Do not ask for private keys in chat.** Secrets live in GitHub Actions (repo + `production` environment).

---

## 2. Architecture (short)

| Area | Path | Role |
|------|------|------|
| App UI / state | `lib/` | Flutter client (Provider, features/) |
| Tunnel / sub / updates | `lib/core/services/` | sing-box, subscription, SoftProbe, updates |
| Server panel | `server/panel.py` → live `/opt/k-pax/panel.py` | Subs, payments hooks, updater versions |
| Ops scripts | `server/k-pax-*.py`, `tools/_ops_*.py`, `tools/ci/` | Watch/limit/backup + CI remotes |
| Android / iOS / Windows | `android/`, `ios/`, `windows/` | Shells + signing |
| iOS CI | `codemagic.yaml` | TestFlight builds (not GHA) |

**Brands:** K-Pax (`k-pax.space`, `kpax`) · X-Plm (`x-plm.online` / `x-plm.space`, `xplm`).

**Golden rule:** Service path bugs → `server/` / fronts / relay. Universal client bugs → `lib/`. Do not thrash SoftProbe/MTU/DNS/routes to “fix RF”.

---

## 3. Servers and services

| ID | Host | Role | Notes |
|----|------|------|-------|
| panel | `77.221.154.107` | `k-pax`, `kpax-front-relay`, Caddy | Code `/opt/k-pax`, cfg `/etc/k-pax`, DB `/var/lib/k-pax/k-pax.db` |
| de | `31.77.116.51` | exit Reality | enabled |
| fi | `144.31.169.6` | exit Reality | enabled |
| pl | `2.26.225.213` | exit Reality | enabled (2026-11-27); SNI `pl.k-pax.space` — set Cloudflare A DNS-only |
| ru | `195.133.45.167` | front 2443/2444/2445 | enabled (`pl` on 2445) |
| ru2 | `152.228.112.142` | front | enabled (`pl` on 2445) |
| bg | `79.124.7.111` | exit | **`enabled: false`** |

Relay: panel `28443`→DE:443, `28444`→FI:443, `28445`→PL:443. CI SSH user: **`gha`** (limited sudo). Host keys: secret `KPAX_DEPLOY_SSH_KNOWN_HOSTS`.

---

## 4. App versions

| Channel | Version | Notes |
|---------|---------|-------|
| Android sideload (recent) | **1.0.83** | tags `v1.0.83`, `v1.0.83-xplm` |
| Windows | **1.0.81** | tags `v1.0.81-windows`, `v1.0.81-xplm-windows` |
| Known-good rollback | **1.0.70** | operator OK 2026-11-18 |
| Tunnel JSON baseline | **1.0.50** semantics | see `.cursor/rules/known-good-client.mdc` |
| Android signing SHA-256 | `4523e7d0…8885ec` | verified in CI dry-run / client-build |

Live panel updater strings update only when `panel.py` is deployed.

---

## 5. GitHub Actions workflows

All under `.github/workflows/`. Manual start: Actions → workflow → **Run workflow**.

| Workflow | File | Mode | Purpose |
|----------|------|------|---------|
| Diagnostics | `diagnostics.yml` | read-only | Host logs (redacted), services, CPU/RAM/disk, listen ports |
| Health check | `health-check.yml` | read-only | TCP panel/exits/fronts/relay, public HTTP smoke |
| Analytics | `analytics.yml` | read-only | Anonymized counts: subs, payments, events by platform/version |
| Backup | `backup.yml` | **`production` approval** | Encrypted DB+allowlisted cfg → Artifact |
| Deploy | `deploy.yml` | **`production` approval** | Allowlisted `server/*.py` → `/opt/k-pax` + optional restart |
| Rollback | `rollback.yml` | **`production` approval** | Restore `/var/backups/k-pax-ci/pre-deploy-*` |
| Client build | `client-build.yml` | build only | Android (signed APK), Windows bins, iOS Codemagic note |
| Android sign dry-run | `android-sign-dry-run.yml` | build only | Fingerprint check vs published cert |
| VPN build smoke | `vpn-build-smoke.yml` | PR/manual | Debug Android + Windows compile |

### Inputs / confirms

- **Diagnostics:** `targets` = `panel,de,fi,ru,ru2` or `all` (BG may fail).
- **Health:** `include_bg` boolean.
- **Backup:** type `BACKUP`.
- **Deploy:** type `DEPLOY`; `paths` default `panel.py`; `restart` default true.
- **Rollback:** type `ROLLBACK`; optional `backup_name`.
- **Client build:** `android` / `windows` / `android-and-windows` / `ios-codemagic-note`.

### Where results land

- **Artifacts** on the workflow run page (`diagnostics-<run_id>`, `health-<run_id>`, `analytics-<run_id>`, `backup-*.enc`, APKs, etc.).
- Job logs for quick status (`SUMMARY.txt` inside artifacts).
- Secrets never printed; IPs/UUIDs in journal snippets are redacted by remote scripts.

### Secrets (repo + `production` env)

`KPAX_DEPLOY_SSH_KEY`, `KPAX_DEPLOY_SSH_KNOWN_HOSTS`, `KPAX_DEPLOY_HOST`, `KPAX_BACKUP_PASSPHRASE`, `ANDROID_*`.

`production` has required reviewers + short wait — use for backup/deploy/rollback/signed Android. Read-only workflows use **repository** secrets (no approval).

### Remote helpers

`tools/ci/ssh_setup.sh`, `remote_diagnostics.sh`, `remote_health_check.sh`, `remote_analytics.py`, `remote_backup.sh`, `install_gha_access.py`.

---

## 6. Deploy / rollback order

1. Open PR or commit allowlisted `server/*.py` only (no `config.json`, keys, DB).
2. Run **Backup** (`BACKUP`) — download Artifact offline.
3. Run **Deploy** (`DEPLOY`, paths e.g. `panel.py`) — waits for `production` approval.
4. Run **Health check** + **Diagnostics**.
5. If bad: **Rollback** (`ROLLBACK`) then health again.

Never restart production without need. Never delete user data. Never change live VPN node Reality/config without operator agreement.

---

## 7. Client CI notes

- **Android / Windows:** GitHub Actions (`client-build`, `vpn-build-smoke`, `android-sign-dry-run`).
- **iOS K-Pax + X-Plm:** Codemagic (`codemagic.yaml`) — GHA only documents the path.
- Publish (Play / sideload Release / TestFlight / GitHub Release) is **out of band** — separate confirmation; signing must keep the same Android cert fingerprint so updates install over existing apps.

---

## 8. Readiness for ChatGPT (independent ops)

| Capability | Status |
|------------|--------|
| Client code analysis | OK (repo) |
| Server code analysis | OK (`server/` tracked) |
| Read server diagnostics | OK (Artifacts) |
| Client statistics | OK (`analytics.yml`) |
| Prepare fixes | OK (PRs / `server/*.py`) |
| **Launch diagnostics yourself** | OK — Actions → Diagnostics / Health / Analytics → **Run workflow** (no `production` approval). Verified runs linked in §10. |
| **Service access security** | OK — CI user `gha` (limited sudo); **operator admin SSH rotated** 2026-11-27 (old `k-pax-admin` fingerprint retired). Panel→node key `/etc/k-pax/id_ed25519` unchanged. |
| **Autonomous deploy** | Use Backup → Deploy → Health with `production` approval. Smoke path: deploy `ci_deploy_probe.py` with `restart=false`. |

## 9. Limits and open issues

**Limits**

- BG host: no `gha` until node restored.
- Deploy allowlist = `server/*.py` basenames only.
- Analytics schema depends on live SQLite tables (`client_events`, `payments`, …).
- Do not change SoftProbe / MTU / DNS / routes / VPN architecture unless the bug is proven client-universal.
- Deploy/Rollback/Backup require human approval on GitHub Environment `production` (by design).

**Open incident (2026-11-26)**

- Front → relay → EU SoftProbe often **204**.
- **Client → RU front** Reality SoftProbe intermittent **000** — fix inbound/UUID/SNI on fronts, not Flutter.
- BG offline.

---

## 10. Key files

| Path | Why |
|------|-----|
| `AGENTS.md` | Project rules |
| `.cursor/rules/known-good-client.mdc` | Rollback / tunnel |
| `server/panel.py` | Subs, Happ, updater |
| `lib/core/services/tunnel_config.dart` | sing-box JSON |
| `lib/core/services/tunnel_connectivity.dart` | SoftProbe + Clash |
| `.github/workflows/*.yml` | Ops + build CI |
| `tools/ci/*` | Remote collect/deploy helpers |

---

## 11. Immediate playbook for ChatGPT

1. **Actions** → **Diagnostics** / **Health check** / **Analytics** → Run workflow → download Artifacts (you do not need Cursor).  
2. If path broken: patch `server/` in a PR; do not edit SoftProbe first.  
3. After review: **Backup** (`BACKUP`) → **Deploy** (`DEPLOY`, approval) → re-run health. First smoke: `paths=ci_deploy_probe.py`, `restart=false`.  
4. Client builds via **Client build**; iOS via Codemagic; **no publish** unless operator asks.

### Verified acceptance runs (2026-11-27)

- Diagnostics: https://github.com/uvarov89/k-pax/actions/runs/45962067665  
- Health: https://github.com/uvarov89/k-pax/actions/runs/45962074072  
- Analytics: https://github.com/uvarov89/k-pax/actions/runs/45962079934  

End of handoff.

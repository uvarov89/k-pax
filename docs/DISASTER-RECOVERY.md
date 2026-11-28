# Disaster recovery

**Rule:** no destructive production tests. Prefer backup → change → verify → rollback. Secrets never in chat.

## Off-panel backup (encrypted)

| Store | What | How |
|-------|------|-----|
| GitHub Actions artifact | AES-256-CBC encrypted tar (DB + full `config.json` + panel py + node sing-box + units) | `/kpax backup` + `CONFIRM: BACKUP` or weekly schedule |
| Passphrase | `KPAX_BACKUP_PASSPHRASE` (Actions secret) | Phone: never paste into chat |
| Panel local | `/var/backups/k-pax-ci/pre-deploy-*` | code trees only |

Integrity: Backup workflow SHA-checks SCP, encrypts, decrypts on runner, `PRAGMA integrity_check`, wipes plaintext, uploads `.enc` (90-day retention).

Isolated restore: `/kpax restore-drill` + `CONFIRM: RESTOREDRILL` — decrypt+verify only, **no write to VPS**.

## Scenarios

| Scenario | First actions | Escalate |
|----------|---------------|----------|
| sing-box down on one exit | `/kpax node-ops action=diag|validate-singbox|restart` + CONFIRM | Provider reboot (RuVDS API or phone) |
| Panel `k-pax` down | diag panel; restart `k-pax` | Restore from encrypted artifact on new/same host |
| TCP relay down | restart `kpax-front-relay` | Check UFW 28443-45 |
| One VPN exit unreachable | health + e2e; disable node only with operator confirm | Provider reboot |
| RU / RU2 down | diag; clients may use direct EU | RuVDS reboot API / AdminVPS phone |
| User sync drift | `/kpax e2e-maintain` + CONFIRM (not plain e2e) | |
| DB damaged | Stop writes; restore-drill first; restore with confirm | Never overwrite live without approval |
| Bad panel code deploy | `/kpax rollback` + CONFIRM | |
| Bad allowlisted config apply | `/kpax config action=rollback kind=…` + `CONFIRM: CONFIGOPS`; or wait for deadman timer | Prefer `diff` + `dry_run` first; network kinds arm local deadman |
| Cert expired | diag certs; renew LE | Phone CF/Namecheap if DNS blocked |
| DNS error | `/kpax dns action=list` + CONFIRM | CF mobile app |
| Panel VPS lost | **New VPS rebuild** (below) | |
| GitHub Actions down | Phone: provider consoles + CF app + laptop SSH if available | |

## Full rebuild on a new admin VPS

1. Provision Ubuntu LTS VPS; SSH key-only root.  
2. Install Caddy, Python3, sqlite3, sing-box (if relay colocated), UFW.  
3. Decrypt latest Actions backup artifact on a **scratch** machine; verify integrity.  
4. Restore `/var/lib/k-pax/k-pax.db`, `/etc/k-pax/config.json` (full secrets), panel `*.py` to `/opt/k-pax/`.  
5. Install systemd units from backup `cfg/`; start `k-pax` then Caddy.  
6. Point Cloudflare A for `k-pax.space` / `sub.k-pax.space` DNS-only or as designed → new IP (`/kpax dns` or CF app).  
7. Reinstall `gha` + `/usr/local/lib/kpax-ci` from repo `tools/ci/install_gha_access.py`.  
8. Update GitHub secret `KPAX_DEPLOY_HOST` / known_hosts.  
9. `/kpax health` + `/kpax e2e`.  
10. Re-sync users to exits (`e2e-maintain` or panel maintenance).

**Do not** restore node sing-box blindly over live exits without diff — prefer panel-driven user sync; use `nodes/*.sing-box.json` from backup only when rebuilding a dead exit.

## Config ops safety net

Allowlisted kinds only (`singbox`, `caddy`, `relay-unit`, `kpax-unit`, `panel-config`, `ci-drill`).  
Every real `config-apply`: validate → backup under `/var/backups/k-pax-ci/config-<kind>-pre-*` → atomic install → restart only the mapped unit → optional SoftProbe e2e → **deadman** timer (local systemd) restores backup if not cancelled (covers SSH loss after network edits).

Isolated drill: `kind=ci-drill` → `/etc/k-pax/ci-drill.conf` (not VPN traffic).

## Phone confirmation

1. ChatGPT posts `/kpax …` + `CONFIRM: …` on an Issue.  
2. GitHub mobile → Actions → pending **production** Environment → Approve.  
3. Open run URL from bot comment for logs (no ZIP required).

## When Actions is down

1. Cloudflare / registrar apps for DNS.  
2. RuVDS / AdminVPS / VPSPay Telegram for power.  
3. Defer code deploy until Actions or laptop returns.

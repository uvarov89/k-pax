# Disaster recovery

**Rule:** no destructive production tests. Prefer backup → change → verify → rollback. Secrets never in chat.

## Scenarios

| Scenario | First actions | Escalate |
|----------|---------------|----------|
| sing-box down on one exit | `/kpax node-ops action=diag targets=<id>` then `validate-singbox`; `restart service=sing-box` + CONFIRM | Provider reboot if host dead |
| Panel `k-pax` down | `/kpax diag panel`; `node-ops restart service=k-pax` | Restore from encrypted Actions backup artifact |
| TCP relay down | diag panel; restart `kpax-front-relay` | Check UFW 28443-45 |
| One VPN exit unreachable | health + e2e; temporarily steer clients via panel node `enabled` **only with operator confirm** | Replace host later |
| RU / RU2 down | diag ru,ru2; clients may still use direct EU | Sync media cert if TLS camouflage broken |
| User sync drift | `node-ops action=sync-users targets=panel` | Compare user counts via analytics (no PII) |
| DB damaged | Stop writes; restore encrypted backup to isolated path first | Never overwrite live DB without confirm |
| Bad config deploy | `/kpax rollback` + CONFIRM | `list-backups` for stamp |
| Cert expired | diag cert section; renew LE on owner host; sync media to ru2 | DNS/HTTP-01 from phone provider UI if needed |
| DNS error | `/kpax dns` list (CONFIRM) / Cloudflare dashboard | Keep Reality records DNS-only |
| Panel VPS lost | Rebuild from docs + restore backup artifact + DNS cutover | Provider snapshot if available |
| GitHub Actions unavailable | Operator laptop SSH + local `kpax-ci` copies | Phone: provider console only |

## Backup locations

| Store | Contents | Access |
|-------|----------|--------|
| Actions artifact (`backup.yml`) | Encrypted tar (AES-256-CBC) | GitHub + `KPAX_BACKUP_PASSPHRASE` |
| Panel `/var/backups/k-pax-ci/` | pre-deploy / pre-rollback code trees | `list-backups` / rollback |
| Off-panel copy | **PARTIAL** — rely on Actions artifacts retention; operator should download periodically to phone/cloud **NEEDS VERIFY** |

## Isolated restore drill

1. Decrypt artifact on a **non-production** scratch VM.  
2. Open SQLite read-only; confirm schema.  
3. Do **not** point live Caddy at scratch.  
Status of last drill: **NOT TESTED** in this pass (no scratch VM provisioned).

## When Actions is down (phone)

1. Cloudflare / registrar DNS apps.  
2. VPS provider power cycle.  
3. Telegram watch alerts from exit `k-pax-watch`.  
4. Defer code deploy until Actions or laptop returns.

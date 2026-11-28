# Acceptance tests — remote ChatGPT ops

Statuses: `VERIFIED` / `PARTIAL` / `FAILED` / `NOT TESTED`.

| # | Capability | Status | Evidence |
|---|------------|--------|----------|
| 1 | Issues gateway + run URL | VERIFIED | [#12](https://github.com/uvarov89/k-pax/issues/12) → [46034378616](https://github.com/uvarov89/k-pax/actions/runs/46034378616) |
| 2 | Diagnostics | VERIFIED | [46034295380](https://github.com/uvarov89/k-pax/actions/runs/46034295380) |
| 3 | CI-E2E account | VERIFIED | dedicated user + env; maintain via `e2e-maintain.yml` |
| 4 | SoftProbe map (read-only e2e) | VERIFIED | DE/FI OK; PL FAIL honest red ([46123390878](https://github.com/uvarov89/k-pax/actions/runs/46123390878)) |
| 5 | PL RCA notes | PARTIAL | KNOWN-ISSUES; no PL config change |
| 6 | Encrypted backup + integrity | VERIFIED | [46124869589](https://github.com/uvarov89/k-pax/actions/runs/46124869589) |
| 7 | Isolated restore drill | VERIFIED | [46124873224](https://github.com/uvarov89/k-pax/actions/runs/46124873224) |
| 8 | Deploy via `kpax-ci` | VERIFIED | [46125540435](https://github.com/uvarov89/k-pax/actions/runs/46125540435) |
| 9 | Rollback via `kpax-ci` | VERIFIED | [46126028116](https://github.com/uvarov89/k-pax/actions/runs/46126028116) |
| 10 | Production Environment approval | VERIFIED | reviewers + wait_timer exercised |
| 11 | Provider inventory workflow | VERIFIED | [46123387272](https://github.com/uvarov89/k-pax/actions/runs/46123387272) |
| 12 | Cloudflare DNS ops | FAILED (secrets) | [46123394596](https://github.com/uvarov89/k-pax/actions/runs/46123394596) — re-run after secrets |
| 13 | RuVDS API status/reboot | NOT TESTED | hardware reboot is **manual** |
| 14 | Weekly off-VPS backup schedule | PARTIAL | cron in `backup.yml` |
| 15 | Read-only e2e separated from ensure/sync | VERIFIED | `vpn-e2e.yml` SoftProbe only |
| 16 | Sanitized config-get (fleet) | VERIFIED | [46131049117](https://github.com/uvarov89/k-pax/actions/runs/46131049117) — panel/de/fi/pl/ru/ru2 `STATUS=OK`, structure only |
| 17 | Config apply dry-run (`ci-drill`) | VERIFIED | [46131071811](https://github.com/uvarov89/k-pax/actions/runs/46131071811) |
| 18 | Config apply + deadman cancel (`ci-drill`) | VERIFIED | [46131082781](https://github.com/uvarov89/k-pax/actions/runs/46131082781) — isolated file only |
| 19 | Config rollback (`ci-drill`) | VERIFIED | [46131906402](https://github.com/uvarov89/k-pax/actions/runs/46131906402) |
| 20 | Issues gateway `config-get` | VERIFIED | [#12 comment](https://github.com/uvarov89/k-pax/issues/12#issuecomment-7237507585) → [46132396809](https://github.com/uvarov89/k-pax/actions/runs/46132396809) |
| 21 | Manage without laptop | PARTIAL | config-ops + DR verified; live VPN kinds still need explicit agree |
| 22 | Deep diagnose + inline logs (PL) | VERIFIED | [46135402361](https://github.com/uvarov89/k-pax/actions/runs/46135402361) — honest `STATUS=FAIL`; front Reality fail + PL DNS-to-127.0.0.1; DE/FI OK; **no PL mutate** |
| 23 | In-place config-patch dry-run | VERIFIED | [46135857661](https://github.com/uvarov89/k-pax/actions/runs/46135857661) — `ci-drill` |
| 24 | Deadman auto-fire drill | VERIFIED | [46135409109](https://github.com/uvarov89/k-pax/actions/runs/46135409109) — restored `drill_version=1` |
| 25 | sync-users no false OK on partial fail | VERIFIED (code) | exits non-zero if any node fails (`eaf35ef`) |

## Key config-ops runs (2026-11-28)

| Check | Run |
|-------|-----|
| config-get singbox fleet | https://github.com/uvarov89/k-pax/actions/runs/46131049117 |
| ci-drill dry-run apply | https://github.com/uvarov89/k-pax/actions/runs/46131071811 |
| ci-drill real apply + deadman cancel | https://github.com/uvarov89/k-pax/actions/runs/46131082781 |
| ci-drill rollback | https://github.com/uvarov89/k-pax/actions/runs/46131906402 |

## Earlier DR runs

| Check | Run |
|-------|-----|
| Backup | https://github.com/uvarov89/k-pax/actions/runs/46124869589 |
| Restore drill | https://github.com/uvarov89/k-pax/actions/runs/46124873224 |
| Deploy / Rollback | https://github.com/uvarov89/k-pax/actions/runs/46125540435 / [46126028116](https://github.com/uvarov89/k-pax/actions/runs/46126028116) |

## Operator notes

1. Live `singbox` / Reality / relay apply: only with explicit agree; drills use `kind=ci-drill`.  
2. Hardware VPS reboot: manual.  
3. Commit: `d0e6475` (config-ops).

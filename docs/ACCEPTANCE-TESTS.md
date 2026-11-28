# Acceptance tests — remote ChatGPT ops

Statuses: `VERIFIED` / `PARTIAL` / `FAILED` / `NOT TESTED`.

| # | Capability | Status | Evidence |
|---|------------|--------|----------|
| 1 | Issues gateway + run URL | VERIFIED | [#12](https://github.com/uvarov89/k-pax/issues/12) → [46034378616](https://github.com/uvarov89/k-pax/actions/runs/46034378616) |
| 2 | Diagnostics | VERIFIED | [46034295380](https://github.com/uvarov89/k-pax/actions/runs/46034295380) |
| 3 | CI-E2E account | VERIFIED | dedicated user + env; maintain via `e2e-maintain.yml` |
| 4 | SoftProbe map (read-only e2e) | VERIFIED | DE/FI OK; PL FAIL honest red ([46123390878](https://github.com/uvarov89/k-pax/actions/runs/46123390878)) |
| 5 | PL RCA notes | PARTIAL | KNOWN-ISSUES; no PL config change |
| 6 | Encrypted backup + integrity | VERIFIED | [46124869589](https://github.com/uvarov89/k-pax/actions/runs/46124869589) — `integrity=OK`, nodes/*.sing-box.json, off-panel artifact |
| 7 | Isolated restore drill | VERIFIED | [46124873224](https://github.com/uvarov89/k-pax/actions/runs/46124873224) — sqlite ok, 5 node configs, plaintext wiped |
| 8 | Deploy via `kpax-ci` | VERIFIED | [46125540435](https://github.com/uvarov89/k-pax/actions/runs/46125540435) — `ci_marker.py`, restart=false, healthz=200 |
| 9 | Rollback via `kpax-ci` | VERIFIED | [46126028116](https://github.com/uvarov89/k-pax/actions/runs/46126028116) |
| 10 | Production Environment approval | VERIFIED | API/phone approve path exercised (`required_reviewers` + 5m wait_timer) |
| 11 | Provider inventory workflow | VERIFIED | [46123387272](https://github.com/uvarov89/k-pax/actions/runs/46123387272) |
| 12 | Cloudflare DNS ops | FAILED (secrets) | [46123394596](https://github.com/uvarov89/k-pax/actions/runs/46123394596) — missing `CLOUDFLARE_*` (operator: reconnect and re-run) |
| 13 | RuVDS API status/reboot | NOT TESTED | hardware reboot is **manual**; API optional |
| 14 | Weekly off-VPS backup schedule | PARTIAL | cron in `backup.yml`; first schedule not yet fired |
| 15 | Read-only e2e separated from ensure/sync | VERIFIED | `vpn-e2e.yml` SoftProbe only; `e2e-maintain.yml` gated |
| 16 | Sanitized config-get (fleet) | PENDING | `config-ops.yml` action=get — fill run link after Actions |
| 17 | Config diff + dry-run (`ci-drill`) | PENDING | isolated; no live VPN mutate |
| 18 | Config apply + deadman cancel (`ci-drill`) | PENDING | panel only; auto-cancel after success |
| 19 | Config rollback (`ci-drill`) | PENDING | after apply |
| 20 | Issues gateway `config-get` / `config` | PENDING | after gateway deploy |
| 21 | Manage without laptop | PARTIAL | DR + config-ops path; live VPN kinds still need explicit agree |

## Key runs (2026-11-28)

| Check | Run |
|-------|-----|
| Backup integrity | https://github.com/uvarov89/k-pax/actions/runs/46124869589 |
| Restore drill | https://github.com/uvarov89/k-pax/actions/runs/46124873224 |
| Deploy ci_marker | https://github.com/uvarov89/k-pax/actions/runs/46125540435 |
| Rollback | https://github.com/uvarov89/k-pax/actions/runs/46126028116 |
| Provider inventory | https://github.com/uvarov89/k-pax/actions/runs/46123387272 |
| Read-only E2E | https://github.com/uvarov89/k-pax/actions/runs/46123390878 |
| DNS (needs secrets) | https://github.com/uvarov89/k-pax/actions/runs/46123394596 |

## Operator notes

1. Live `singbox` / Reality / relay apply: only with explicit agree; drills use `kind=ci-drill`.  
2. Hardware VPS reboot: manual (hosting APIs not required).  
3. Cloudflare: re-verify secrets then `/kpax dns`.

Commits: `d67f538`, `f17747e`, `45d372a`, `89cc1b9`, `6e783f3` (+ config-ops commit after push).

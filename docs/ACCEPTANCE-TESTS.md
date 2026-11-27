# Acceptance tests — remote ChatGPT ops

Fill **Status** after each real run: `VERIFIED` / `PARTIAL` / `FAILED` / `NOT TESTED`.

| # | Capability | Status | Evidence |
|---|------------|--------|----------|
| 1 | Issues gateway dispatches + run URL comment | VERIFIED | [#12](https://github.com/uvarov89/k-pax/issues/12) → gateway success → [health 46034378616](https://github.com/uvarov89/k-pax/actions/runs/46034378616) |
| 2 | Fresh diagnostics logs in Actions | VERIFIED | [diagnostics 46034295380](https://github.com/uvarov89/k-pax/actions/runs/46034295380) |
| 3 | Dedicated CI-E2E subscription/env | VERIFIED | `CI-E2E` + `ci-e2e.env`; synced to de/fi/pl/ru/ru2; ensure step in E2E OK |
| 4 | Per-node SoftProbe map | VERIFIED | [e2e 46034310970](https://github.com/uvarov89/k-pax/actions/runs/46034310970) — DE/FI OK; PL FAIL; honest red |
| 5 | Root-cause notes for failures | PARTIAL | KNOWN-ISSUES: RU2 Reality fail + PL hop/direct SoftProbe 000; **no PL config change** |
| 6 | Server journals via diag | VERIFIED | diagnostics run above (redacted journals in log stream) |
| 7 | Encrypted backup | NOT TESTED | needs phone `CONFIRM: BACKUP` + production approval |
| 8 | Test deploy via wrapper | NOT TESTED | code path `kpax-ci deploy-install`; needs approval |
| 9 | Test rollback via wrapper | NOT TESTED | code path `kpax-ci rollback`; needs approval |
| 10 | Restore from encrypted backup (isolated) | NOT TESTED | no scratch VM |
| 11 | Critical confirm from phone | NOT TESTED | owner Environment approval UI |
| 12 | Manage without owner laptop | PARTIAL | Gateway+read-only VERIFIED; mutate path waiting phone approvals |

## Runs (this pass)

| Check | Run |
|-------|-----|
| Gateway #12 | https://github.com/uvarov89/k-pax/actions/runs/46034364950 |
| Health (via gateway) | https://github.com/uvarov89/k-pax/actions/runs/46034378616 |
| Health (manual) | https://github.com/uvarov89/k-pax/actions/runs/46034288084 |
| Diagnostics | https://github.com/uvarov89/k-pax/actions/runs/46034295380 |
| Analytics | https://github.com/uvarov89/k-pax/actions/runs/46034303399 |
| VPN E2E (honest PL red) | https://github.com/uvarov89/k-pax/actions/runs/46034310970 |

Commits: `fdfb0fd`, `a6a5dc3`.

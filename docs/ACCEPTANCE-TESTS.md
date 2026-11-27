# Acceptance tests — remote ChatGPT ops

Fill **Status** after each real run: `VERIFIED` / `PARTIAL` / `FAILED` / `NOT TESTED`.

| # | Capability | Status | Evidence |
|---|------------|--------|----------|
| 1 | Issues gateway dispatches + run URL comment | NOT TESTED | Re-test after push (fix for #8–#11 SyntaxError) |
| 2 | Fresh diagnostics logs in Actions | NOT TESTED | `/kpax diag` |
| 3 | Dedicated CI-E2E subscription/env | VERIFIED (panel) | `CI-E2E` created; `/etc/k-pax/ci-e2e.env` with per-exit PBK/SID; synced via `k-pax-user.py add` to de/fi/pl/ru/ru2 |
| 4 | Per-node SoftProbe map | VERIFIED (SSH e2e) | Panel `kpax-ci e2e`: DE front+direct OK; FI direct OK; FI/PL front + PL direct FAIL; honest `STATUS=FAIL` |
| 5 | Root-cause notes for failures | PARTIAL | See KNOWN-ISSUES (RU2 Reality + PL hop); no PL config change |
| 6 | Server journals via diag | NOT TESTED | needs Actions after git push |
| 7 | Encrypted backup | NOT TESTED | `/kpax backup` + CONFIRM + approval |
| 8 | Test deploy via wrapper | NOT TESTED | code uses `deploy-install`; needs approved run |
| 9 | Test rollback via wrapper | NOT TESTED | code uses `kpax-ci rollback` |
| 10 | Restore from encrypted backup (isolated) | NOT TESTED | no scratch VM this pass |
| 11 | Critical confirm from phone | NOT TESTED | Environment approval UI |
| 12 | Manage without owner laptop | PARTIAL | Path designed; end-to-end phone drill pending after push |

## Prior verified baselines (pre this mega-pass)

| Check | Run |
|-------|-----|
| Diagnostics | https://github.com/uvarov89/k-pax/actions/runs/46009049713 |
| Health green | https://github.com/uvarov89/k-pax/actions/runs/46009456544 |
| Analytics | https://github.com/uvarov89/k-pax/actions/runs/46009063235 |
| VPN E2E (old PL-advisory green) | https://github.com/uvarov89/k-pax/actions/runs/46010045313 |

Replace with new runs after code push. Honest E2E may now **fail** while PL SoftProbe is red — that is expected until PL RCA.

# Handoff for next AI agent (K-Pax / X-Plm)

**Date:** 2026-11-27  
**Operator language:** Russian  
**Repo:** [uvarov89/k-pax](https://github.com/uvarov89/k-pax)  
**Site frontend:** not in this repo.

## Doc map (start here)

| Doc | Purpose |
|-----|---------|
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | Inventory + diagram |
| [OPS-COMMANDS.md](OPS-COMMANDS.md) | `/kpax` + `kpax-ci` |
| [DIAGNOSTICS.md](DIAGNOSTICS.md) | Outage order + E2E layers |
| [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) | Failure scenarios |
| [OPS-PROVIDER-APIS.md](OPS-PROVIDER-APIS.md) | Cloudflare / VPS APIs |
| [KNOWN-ISSUES.md](KNOWN-ISSUES.md) | Open defects |
| [ACCEPTANCE-TESTS.md](ACCEPTANCE-TESTS.md) | VERIFIED matrix |
| [OPS-RUNBOOK.md](OPS-RUNBOOK.md) | Human SSH / panel detail |

## Your access

| Access | You |
|--------|-----|
| GitHub code / PRs / Actions logs | Yes |
| Issues `/kpax` gateway | Yes (authorized login) |
| Direct SSH / Cursor laptop | Do not rely on it |
| Secrets in chat | **Never** |
| Store / TestFlight publish | Only with explicit operator confirm |
| Change PL VPN config | **Forbidden** until SoftProbe RCA + confirm |

## ChatGPT phone path

```text
/kpax health
/kpax diag panel,de,fi,pl,ru,ru2
/kpax analytics
/kpax e2e
```

Dangerous (include confirm token; approve Environment `production` on phone):

```text
/kpax backup
CONFIRM: BACKUP
```

Gateway: `.github/workflows/ops-gateway.yml` — must **not** redeclare `core` (injected by github-script).

## Architecture short

Service path bugs → `server/` / fronts / relay / nodes.  
Universal client bugs → `lib/` (do not thrash client for RF SoftProbe).  
CI remotes: `tools/ci/wrappers/` → `/usr/local/lib/kpax-ci/kpax-ci` only sudo for `gha`.

## Fleet (non-secret)

| ID | IP | Role |
|----|-----|------|
| panel | 77.221.154.107 | panel + relay + Caddy |
| de | 31.77.116.51 | exit |
| fi | 144.31.169.6 | exit |
| pl | 2.26.225.213 | exit — SoftProbe front path FAIL |
| ru | 195.133.45.167 | front |
| ru2 | 152.228.112.142 | front |
| bg | 79.124.7.111 | disabled |
| xplm | 45.133.209.80 | brand edge |

E2E: dedicated `CI-E2E` + `/etc/k-pax/ci-e2e.env` via `kpax-ci ensure-e2e-env`.

## App versions (do not change in ops-only tasks)

Android live **1.0.84**; Windows **1.0.81**; rollback **1.0.70**.

## Immediate priorities for ChatGPT

1. Verify Issues gateway with a new `/kpax health` (expect run URL comment).  
2. Run `/kpax e2e`; expect possible red on PL — collect fail logs, do not “fix” PL yet.  
3. Keep deploy/rollback on wrappers only.  
4. Expand acceptance matrix links after each verified run.

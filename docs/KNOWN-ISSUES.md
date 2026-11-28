# Known issues

| ID | Severity | Status | Notes |
|----|----------|--------|-------|
| PL SoftProbe via `front-pl:2445` + direct PL | High | Open (RCA refreshed 2026-11-28) | Deep-diagnose: PBK/SID match panel↔`ru`/`ru2` `to-pl` (relay `panel:28445`); CI-E2E present on PL. **`front-pl` SoftProbe: `reality verification failed`**. **`direct-pl`**: Reality inbound accepts CI-E2E then **DNS fails** — sing-box resolves via `127.0.0.1:53` → `connection refused` (host resolvectl has 1.1.1.1/8.8.8.8). Hops TCP OPEN. **No PL config change without operator confirm.** |
| RU2 front Reality vs panel front PBK | High | Open | Same `sk_sha12` as RU but SoftProbe from panel keys fails on RU2 only — investigate camouflage/UUID/sync; consider DNS single-A or health-gated media. |
| Issues gateway #8–#11 no feedback | High | Fixed in code | Cause: `ops-gateway.yml` redeclared `const core` inside `github-script` → SyntaxError. Rewrite avoids redeclare; adds run URL + dedupe. **Needs fresh Issue verification after push.** |
| E2E used last-active customer UUID | High | Fixed in code | Now dedicated `CI-E2E` + `ensure-e2e-env`. |
| E2E borrowed front PBK/SID for exits | High | Fixed in code | Missing keys → `SKIP_NO_KEYS`. |
| FI individual PBK/SID omitted in env writer | Med | Fixed in code | Writer emits `E2E_FI_PBK/SID` from node config. |
| E2E deleted sing-box fail logs | Med | Fixed in code | Persist under `/var/log/k-pax-ci/e2e/`. |
| HTTP 000 opaque | Med | Fixed in code | HINT + fail log. |
| Egress IP not always checked | Med | Fixed in code | Compare to `E2E_EXPECT_*` when set. |
| PL failure still greened workflow | High | Fixed in code | `PL_PATH=FAIL` ⇒ `STATUS=FAIL`. |
| `deploy.yml`/`rollback.yml` raw sudo | High | Fixed in code | Use `kpax-ci deploy-install` / `rollback`. |
| BG exit offline | Low | Accepted | `enabled: false`. |
| Cloudflare scoped token | Med | Optional | Until secret set, DNS ops limited. |
| Multi-region E2E vantage | Low | Open | Single panel vantage today. |

## Client

| Item | Notes |
|------|-------|
| Live Android updater | **1.0.84** |
| Known-good rollback | **1.0.70** |
| This task | **No client code / release changes** |

# QA findings — K-Pax + X-Plm, Android + Windows (17 Nov 2026)

**Baseline:** GitHub `main` SHA `b8b1e7cb0d28cfec99cbec38fc46931c7d633556`, published 1.0.65. **QA branch:** `qa/four-clients-connectivity-audit-20261117`, PR #3. No production server or actual user device changed. This report separates proven source/test defects from hypotheses and E2E blockers.

## Verified by CI

| Check | Status | Evidence | What it proves |
|---|---|---|---|
| All K-Pax/common Dart/widget tests on Linux | PASS | https://github.com/uvarov89/k-pax/actions/runs/44053942013 | Pure Dart/widget test scenarios, not real TUN |
| All X-Plm branded Dart/widget tests on Linux | PASS | same run | Tests compiled with `BRAND=xplm` rather than K-Pax default |
| All K-Pax/common and X-Plm branded tests on Windows | PASS | same run | Windows Dart/widget tests, not real networking |
| Android Play debug build (kpaxPlay, xplmPlay) | PASS | same run | Both Android manifests/packages compile; no sideload permission |
| Native `sing-box check`: seven synthetic protocols × two IPv6 modes | PASS | https://github.com/uvarov89/k-pax/actions/runs/44054515490 | Config syntax parses on 1.12.12 and 1.13.21; no actual remote handshake |
| Curated VPN / subscription / failover tests and analyzer | PASS | https://github.com/uvarov89/k-pax/actions/runs/44054515458 | Selected logic/static checks |
| Actual same-node HTTPS, external IP, DNS leaks, UDP, Telegram via 4 apps | BLOCKED / NOT RUN | requires a real Android device and Windows machine/VM with a disposable account | **Do NOT claim VPN operational** |
| Signed APK update over 1.0.65 (original certificate) | BLOCKED / NOT RUN | signing key only on release workstation | Original-key signing not available in CI |
| Live /app/login, /s/token, /app/android, /app/windows for both brands | BLOCKED / NOT RUN | endpoints inaccessible by current remote inspection | No verified live backend contract |
| Persistent Windows kill switch | FAIL / UNIMPLEMENTED | `lib/core/services/windows_platform.dart` | No fail-closed leak protection |

## Confirmed code defects and fixes in PR #3 (not yet released)

1. **P0 — lost viable backup profile**: `VpnController._endpointKey` used only country/protocol/host/port; two distinct profiles with different auth/SNI/transport on the same IP:port were treated as identical. Fixed key to include outbound identity (in memory only), plus regression test `test/failover_same_endpoint_test.dart`. Did not expose auth material to diagnostics.
2. **P0 — unbounded spare retry loop**: `trySpares` called `_spareFor` repeatedly when `tryStart` had already exhausted its eight attempts/deadline, without marking candidate tried. Could hang on Connecting indefinitely. Added budget/deadline to loop and test with 12 failing nodes.
3. **P1 — test suite missed white-label behavior**: calling `flutter test` without `BRAND=xplm` executes X-Plm visual test as K-Pax and fails; previous selective CI didn't cover the entire set. Split suite by brand on Linux and Windows.
4. **P1 — native Windows widget test leaked OS shell process**: `WindowsFirewall.clear` called from settings widget tests, leaving a fake-async timer and invoking real `netsh`. Test harness now sets `WindowsFirewall.disableForTests=true` and restores after. Real firewall behavior still requires an OS integration test.

## Additional confirmed source observations / risks NOT fixed yet

5. **P0 — Windows Connected can be false-positive**: `WindowsSingboxVpnService.verifyConnectivity` treats many errors reading `/connections` (null process/secret, non-200, invalid JSON, network/API exceptions) as success if a public HTTPS request worked. A request can succeed through clearnet when Wintun routes are absent. Aggregate Clash counters do not prove specific test packets used outbound proxy. Must verify **intended exit IP and route**, not only HTTPS. Issue #5.
6. **P0 — customer incident not yet reproduced under same conditions**: claim from customers is credible; no device-side logs or same-node comparison against Hiddify/Happ/INCY/v2rayN available. Exact root cause remains unknown. Issue #4.
7. **P1 — Android underlay/network lifetime**: `DefaultNetworkMonitor.kt` / `DefaultNetworkListener.kt` use `GlobalScope` and synchronous `Thread.sleep` in network callbacks, which complicates Wi-Fi↔5G transitions, cancellations and races. *Risk*, not demonstrated root cause. Libbox 1.12.12 Android differs from sing-box 1.13.21 Windows; parser compatibility alone doesn't validate Android `VpnService`.
8. **P1 — protocol-agnostic TUN assumptions**: fixed TUN MTU 9000, default IPv4-only, explicit IPv6/QUIC rejection, DNS direct via UDP/53, remote TCP via proxy. Must test against restrictive carriers and compare with functioning third-party configs instead of changing all simultaneously. `tunnel_config.dart`.
9. **P1 security — Windows persistent Kill switch unavailable**; UI warns; no claim of leak protection on tunnel drop. Implement and test WFP or safe equivalent separately.
10. **P1 release / update lifecycle**: source Android APK CDN redirect fixed in main, but old installed versions still need manual matching-signature APK once; Windows/Android backend version endpoints and signing/installer parity must be checked. Current 1.0.65 and upcoming 1.0.66 are not proof of successful update on-device.
11. **P2 — `VpnController.connect()` returns true even when connection ends in error**, which may mislead callers interpreting bool as outcome. Check all call-sites before changing contract.
12. **P2 — formatting / lint debt**: audit formatter found ~47/90 Dart files need formatting, static analysis warnings include dead-code in `lib/app/pulse_app.dart` and unused test import; maintain in separate change, not a network hotfix.

## Application-level gates (all currently BLOCKED for real E2E)

### K-Pax Android
- Same node VLESS/REALITY and reserve gRPC/WS/TUIC/Hysteria2 vs Hiddify/Happ, on 5G and Wi-Fi.
- VPN permission, TUN routes/protect, DNS leak, real exit-IP, Telegram after wake, reconnect, split tunnel.
- Original signing certificate, upgrade without uninstall, preserved subscription.

### X-Plm Android
- Same as K-Pax, plus email-only login, X-Plm host/API/appId and strict cross-brand APK/token isolation, UI and deep-link brand parity.

### K-Pax Windows
- Same node vs v2rayN/Happ; verify Wintun interface, routes and DNS, proxy-destined egress not clearnet; UAC/normal user and installed old firewall rules, ten reconnects, sleep, Inno update.
- Do not mark Kill switch as safe fail-closed until independently verified.

### X-Plm Windows
- All Windows tests with separate native `APP_BRAND=xplm` and Dart `BRAND=xplm`; coexistence with K-Pax, separate folders/pids/installer/deeplinks, email-only and endpoints.

## How to capture reproducible, local diagnostic evidence

On Windows, run `scripts/qa-windows-exit-parity.ps1 -Brand kpax -Phase baseline` with VPN off; then repeat with `thirdparty` and `firstparty` on the same node. Repeat brand xplm. The script compares egress IPs without sending credentials.
On Android, `scripts/qa-android-native-diagnostics.ps1 -Brand kpax` or `-Brand xplm` from Windows PC with authorized ADB; collect only on failing session. Raw logs can contain local network identities: keep private, redact before reporting. Neither script has executed on a real user device yet.

## Release decision

**NO-GO / not ready to declare functional**: reproducible customer outage + P0 exit-IP parity not tested. CI PASS is necessary but insufficient. Changes are confined to a draft PR; real production release awaits full device validation.

# K-Pax and X-Plm: Android / Windows / iOS VPN repair

## 1.0.60 hotfix (Hiddify-aligned data-plane)

Field reports after 1.0.59: same subscription works in Hiddify, still fails in
branded clients on Android and Windows (iOS expected to share the JSON).

Deltas taken from Hiddify-app defaults + hiddify-core `setInbound` / `setDns`
(patterns only — not copied source):

1. **Remote DNS = TCP `8.8.8.8` via proxy** — Hiddify Flutter default
   (`tcp://8.8.8.8`). UDP DNS through VLESS/Reality often stalls; 1.0.59 kept UDP.
2. **Direct DNS = UDP `1.1.1.1` via direct** — not `local` alone. Under full TUN,
   OS local DNS commonly points into the tunnel and blackholes bypass / host
   resolution. Keep `dns-local` (`type: local`) as bootstrap peer.
3. **TUN `172.19.0.1/28`, MTU 9000, `endpoint_independent_nat: true`** — match
   Hiddify-core inbound defaults (was `/30` + 1400).
4. **Port 53 → `hijack-dns`** in addition to sniffed DNS protocol (Hiddify steers
   port 53 into dns-out).
5. **Android `override_android_vpn: true`** — Hiddify route option under VpnService.
6. **Windows `strict_route` still forced false** — no safe WFP kill switch yet.
7. **iOS post-connect settle** before HTTPS probe (parity with Android/Windows).

Keep modern DNS schema (`type: local` / `udp` / `tcp`) for sing-box 1.12.12
(Android Libbox) and 1.13.21 (Windows/iOS). Keep clearnet update/ISP bypasses,
IPv4-only TUN by default, QUIC reject, IPv6 reject unless opted in.

## 1.0.59 hotfix (data-plane)

Field reports after 1.0.58: engine starts / UI may show Connected, but traffic
still fails while Hiddify works on the same subscription.

Root causes addressed in 1.0.59:

1. **Windows `strict_route` lie** — Pro UI disabled kill switch, but
   `ProSettings.killSwitch` still defaulted to `true`, so sing-box enabled
   Windows WFP strict_route rules that break DNS/reconnect. Force
   `strict_route: false` on Windows in `buildTunnelConfig`, hydrate/save
   killSwitch as false, disable X-Plm Windows toggle.
2. **Dual-stack TUN + TCP DNS regression** — c02282a “Hiddify parity” undid the
   proven IPv4-only path but paired TCP DNS with dual-stack ULA. 1.0.59 restored
   IPv4-only + UDP DNS; 1.0.60 keeps IPv4-only and switches remote DNS to TCP.
3. **Probe race** — HTTPS probe settles briefly and retries; Android/Windows
   wait after TUN/Clash ready before probe.
4. **Android TUN iterators** — snapshot Libbox route/address iterators before
   applying VpnService routes (defensive against partial consumption).

## Android Libbox upgrade blocker (1.12.12 → 1.13.21)

iOS/Windows are pinned to sing-box **1.13.21**. Android still uses JitPack
`com.github.singbox-android:libbox:1.12.12` via `flutter_singbox_vpn`.

**Do not bump the Android Gradle pin yet.** Safe path later: build a full
Android Libbox AAR from SagerNet/sing-box `v1.13.21` (gomobile).

Pins: `scripts/singbox-version-pins.env`.

## Security limitation

**Windows persistent kill switch is NOT implemented.** Do not market the
Windows toggle as fail-closed. Post-connect HTTPS probe checks reachability
but does NOT verify exit IP — leak tests remain mandatory.

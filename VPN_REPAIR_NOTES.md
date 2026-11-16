# K-Pax and X-Plm: Android / Windows VPN repair

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
   proven IPv4-only + UDP DNS path (0c9641a / 9db533c). Restore IPv4-only TUN
   by default, UDP DNS with modern 1.12+ schema (`type: udp`), always reject
   IPv6 unless user opts into `Ipv6Mode.enabled`.
3. **Probe race** — HTTPS probe now settles briefly and retries; Android/Windows
   wait after TUN/Clash ready before probe.
4. **Android TUN iterators** — snapshot Libbox route/address iterators before
   applying VpnService routes (defensive against partial consumption).

Keep modern DNS schema (`type: local` / `type: udp`) — legacy `address` fails
on sing-box 1.13.21 without deprecated flags.

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

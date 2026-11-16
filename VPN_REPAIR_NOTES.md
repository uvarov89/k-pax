# K-Pax and X-Plm: Android / Windows VPN repair (candidate)

**Not production verified.** Apply to a dedicated test branch and test on
actual Android and Windows devices before merging or distributing binaries.

## Confirmed native-core failure

The generated config used legacy DNS server `address` entries. The actual
sing-box v1.13.21 native parser fails immediately without the deprecated DNS
feature flag. The shared generator has been migrated to modern `type: local`
and `type: tcp` DNS server objects; native validation is mandatory.

## Android Libbox upgrade blocker (1.12.12 → 1.13.21)

iOS/Windows are pinned to sing-box **1.13.21**. Android still uses JitPack
`com.github.singbox-android:libbox:1.12.12` via `flutter_singbox_vpn`.

**Do not bump the Android Gradle pin yet.** Inspected artifacts:

| Source | Tag | `BoxService` / `Libbox.newService` |
|--------|-----|-------------------------------------|
| JitPack AAR | 1.12.12 | present (current pin) |
| JitPack AAR | 1.13.0 … 1.13.21, 1.14.0 | **missing** (~90–118 MB AARs without VPN host API) |
| GitHub Release AAR | 1.13.21 | **no assets** |
| GitHub Release AAR | 1.14.4 | CommandServer only; no `newService`; larger PlatformInterface |

A naive `1.13.21` Gradle bump would break APK compile (`Libbox.newService` /
`io.nekohasekai.libbox.BoxService` used by `BoxService.kt`). Safe path later:
build a full Android Libbox AAR from SagerNet/sing-box `v1.13.21` (gomobile),
or wait for a complete published AAR; then update PlatformInterface
(`findConnectionOwner` → `ConnectionOwner`, drop `packageNameByUid` /
`uidByPackageName`, CommandServerHandler `serviceStop` /
`writeDebugMessage`).

Pins + CI drift guard: `scripts/singbox-version-pins.env` and
`scripts/check-singbox-version-pins.ps1`. Config smoke still validates
generated JSON against both 1.13.21 and Android 1.12.12.

## Repairs

- Android: fix API 33+ default route fallback, which previously re-checked an
  exhausted Libbox address iterator, and pre-33 fallback for empty route ranges.
- Android/Windows: don't report `Connected` solely because sing-box started.
  Perform an actual DNS-based HTTPS request after TUN startup. If both public
  diagnostic endpoints fail, close the tunnel and use existing node failover.
- Windows: stop creating machine-wide BLOCK-all rules that override the process
  ALLOW rule and can permanently prevent reconnect. Best-effort cleanup before
  VPN start; if existing rules persist, run
  `scripts/cleanup-legacy-kpax-firewall.ps1` as Administrator.
- Does not modify server credentials, subscription tokens, billing, production
  infrastructure, tunnel DNS stack/MTU or protocols.

## Security limitation

**Windows persistent kill switch is NOT implemented by this patch.**
The Windows Kill switch control is now disabled and labeled unavailable.
The old firewall block-all mechanism is disabled because it causes a machine-
wide outage. A verified WFP-based fail-closed design is required before Windows
can advertise a guaranteed kill switch. Do not market the Windows toggle as a
persistent fail-closed guarantee. The post-connect HTTPS probe checks reachability
but does NOT verify traffic egress via the requested country/server, so IP and
DNS leak tests are mandatory.

## Before merge / publish

1. `dart format` affected Dart files, `flutter analyze`, `flutter test`.
2. Build K-Pax and X-Plm for Android and Windows using existing release scripts.
3. On the SAME node/protocol, compare Hiddify and each of the four products.
4. Verify external IP belongs to the desired exit; compare to clearnet IP.
5. Confirm DNS, IPv4, IPv6, UDP, QUIC fallback, split tunnel, Wi-Fi, 5G,
   reconnect, sleep/resume and upgrade from a broken release.
6. Confirm that wrong server credentials never produce a green Connected status.
7. Verify no keys, subscription URLs, tokens or private details appear in logs.
8. Do not merge/release until live tests and Windows kill-switch safety review.

This patch fixes code paths and diagnostics, not a confirmed VPN outage root
cause. The source baseline is main at c02282afb69120922bfde9735b1a48bb3d8999cd.

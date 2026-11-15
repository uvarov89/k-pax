# K-Pax and X-Plm: Android / Windows VPN repair (candidate)

**Not production verified.** Apply to a dedicated test branch and test on
actual Android and Windows devices before merging or distributing binaries.

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

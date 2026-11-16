import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

const kClashPort = 9090;

/// Hiddify-core TUN IPv4 prefix (`172.19.0.1/28`). Narrower `/30` left some
/// Libbox/Android path setups with too little headroom vs Hiddify on the same
/// subscription.
const _tunIpv4 = '172.19.0.1/28';
const _tunIpv6 = 'fdfe:dcba:9876::1/126';

/// Hiddify / sing-box docs default TUN MTU. 1400 was speculative and smaller
/// than every working Hiddify profile we compared.
const _tunMtu = 9000;

/// RU mobile operator portals + OS captive probes. Full-tunnel often breaks
/// Beeline/MTS/etc. until these resolve and connect outside the proxy.
const _ispDirectDomainSuffixes = <String>[
  'beeline.ru',
  'mts.ru',
  'megafon.ru',
  'tele2.ru',
  't2.ru',
  'yota.ru',
  'captive.apple.com',
  'msftconnecttest.com',
];

const _ispDirectDomains = <String>[
  'connectivitycheck.gstatic.com',
];

/// Brand site + GitHub release CDN must stay reachable even when the proxy
/// path is broken — otherwise Connected clients cannot download updates.
List<String> _updateDirectDomainSuffixes() => [
      AppBrand.current.host,
      AppBrand.current.subHost,
      'github.com',
      'githubusercontent.com',
    ];

const _updateDirectDomains = <String>[
  'release-assets.githubusercontent.com',
  'objects.githubusercontent.com',
];

bool _windowsPlatform() => !kIsWeb && Platform.isWindows;
bool _androidPlatform() => !kIsWeb && Platform.isAndroid;

String buildTunnelConfig(
  TunnelNode node,
  ProSettings settings, {
  AppSettings? appSettings,
  bool enableStats = false,
  String? clashSecret,
}) {
  // Default (disabled): IPv4-only TUN + reject IPv6 — matches Hiddify ipv4_only.
  // tunnelOnly: dual-stack TUN + reject IPv6 (Happy-Eyeballs without exit IPv6).
  // enabled: dual-stack TUN, IPv6 may exit via proxy.
  final dualStackTun = settings.ipv6Mode != Ipv6Mode.disabled;
  final allowIpv6Traffic = settings.ipv6Mode == Ipv6Mode.enabled;
  final dnsStrategy = allowIpv6Traffic ? 'prefer_ipv4' : 'ipv4_only';
  final remoteDnsTag = settings.dnsAutomatic ? 'dns-remote' : 'dns-direct';
  // Windows kill-switch UI is disabled (no safe WFP yet), but ProSettings still
  // defaults to killSwitch=true → strict_route WFP rules that break reconnect /
  // local DNS. Never enable strict_route on Windows until a real kill switch.
  // Hiddify enables strict_route by default; they ship a working Windows service.
  final strictRoute = _windowsPlatform() ? false : settings.killSwitch;
  final outbound = Map<String, Object?>.from(node.outbound);
  if (InternetAddress.tryParse(node.host) == null) {
    // Resolve proxy hostname on clearnet (Hiddify dns-direct), never via remote.
    outbound['domain_resolver'] = {
      'server': 'dns-direct',
      'strategy': dnsStrategy,
    };
  }
  return jsonEncode({
    'log': {'level': 'warn', 'timestamp': true},
    'dns': {
      'servers': [
        {
          // Bootstrap / AddressResolver equivalent of Hiddify dns-local.
          'tag': 'dns-local',
          'type': 'local',
          'detour': 'direct',
        },
        {
          // Hiddify direct DNS: UDP to a public resolver via clearnet — not
          // `local` alone (under full TUN, OS local DNS often points into the
          // tunnel and blackholes bypass / proxy-host resolution).
          'tag': 'dns-direct',
          'type': 'udp',
          'server': '1.1.1.1',
          'server_port': 53,
          'detour': 'direct',
        },
        {
          // Hiddify Flutter default remote DNS: TCP via proxy. UDP DNS through
          // VLESS/Reality often stalls while the same node works in Hiddify.
          'tag': 'dns-remote',
          'type': 'tcp',
          'server': '8.8.8.8',
          'server_port': 53,
          'detour': 'proxy',
        },
      ],
      'rules': [
        {
          'domain_suffix': [
            ..._updateDirectDomainSuffixes(),
            ..._ispDirectDomainSuffixes,
          ],
          'domain': [
            ..._ispDirectDomains,
            ..._updateDirectDomains,
          ],
          'server': 'dns-direct',
        },
      ],
      'final': remoteDnsTag,
      'strategy': dnsStrategy,
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'address': dualStackTun ? [_tunIpv4, _tunIpv6] : [_tunIpv4],
        'mtu': _tunMtu,
        'auto_route': true,
        'strict_route': strictRoute,
        // Hiddify sets this; mixed already uses gVisor UDP (endpoint-independent
        // by default for system TCP). Harmless on mixed, helps if stack flips.
        'endpoint_independent_nat': true,
        // mixed is Hiddify's legacy TUN stack default and reliable on Android
        // Libbox 1.12.12 / sing-box 1.13.21.
        'stack': 'mixed',
      },
    ],
    'outbounds': [
      outbound,
      {'type': 'direct', 'tag': 'direct'},
    ],
    if (enableStats && clashSecret != null && clashSecret.isNotEmpty)
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:$kClashPort',
          'secret': clashSecret,
        },
      },
    'route': {
      'auto_detect_interface': true,
      // Hiddify sets OverrideAndroidVPN; lets Libbox treat the underlying NIC
      // correctly when auto_detect_interface runs under VpnService.
      if (_androidPlatform()) 'override_android_vpn': true,
      'default_domain_resolver': {
        'server': remoteDnsTag,
        'strategy': dnsStrategy,
      },
      'rules': _routeRules(appSettings, allowIpv6Traffic: allowIpv6Traffic),
      'final': _finalOutbound(appSettings),
    },
  });
}

List<Map<String, Object?>> _routeRules(
  AppSettings? appSettings, {
  required bool allowIpv6Traffic,
}) {
  final rules = <Map<String, Object?>>[
    {'action': 'sniff'},
    {'protocol': 'dns', 'action': 'hijack-dns'},
    // Hiddify also steers plain port 53 into the DNS outbound; without this,
    // hard-coded resolvers that skip sniff can leak or stall as raw UDP.
    {'port': 53, 'action': 'hijack-dns'},
    {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
    {
      'domain_suffix': [
        ..._updateDirectDomainSuffixes(),
        ..._ispDirectDomainSuffixes,
      ],
      'domain': [
        ..._ispDirectDomains,
        ..._updateDirectDomains,
      ],
      'action': 'route',
      'outbound': 'direct',
    },
    // Reality/VLESS is TCP-first. QUIC (HTTP/3) often stalls through it while the
    // same site works on TCP — reject QUIC so browsers/apps fall back to HTTPS.
    {'protocol': 'quic', 'action': 'reject'},
  ];
  if (!allowIpv6Traffic) {
    // Proven: reject IPv6 so apps fall back to IPv4 through the proxy.
    rules.add({'ip_version': 6, 'action': 'reject'});
  }
  final names = _windowsProcessNames(appSettings);
  if (names.isEmpty || appSettings == null) return rules;
  if (appSettings.splitTunnelMode == SplitTunnelMode.excludeSelected) {
    rules.add({
      'process_name': names,
      'action': 'route',
      'outbound': 'direct',
    });
  } else if (appSettings.splitTunnelMode == SplitTunnelMode.includeOnly) {
    rules.add({
      'process_name': names,
      'action': 'route',
      'outbound': 'proxy',
    });
  }
  return rules;
}

String _finalOutbound(AppSettings? appSettings) {
  if (appSettings != null &&
      !kIsWeb &&
      Platform.isWindows &&
      appSettings.splitTunnelMode == SplitTunnelMode.includeOnly &&
      _windowsProcessNames(appSettings).isNotEmpty) {
    return 'direct';
  }
  return 'proxy';
}

List<String> _windowsProcessNames(AppSettings? appSettings) {
  if (appSettings == null || kIsWeb || !Platform.isWindows) return const [];
  if (appSettings.splitTunnelMode == SplitTunnelMode.allApps) return const [];
  final seen = <String>{};
  for (final raw in appSettings.splitTunnelPackages) {
    final name = raw.trim().toLowerCase();
    if (RegExp(r'^[a-z0-9._ -]+\.exe$').hasMatch(name)) seen.add(name);
  }
  return seen.toList();
}

Future<int?> measureTcp(String host, int port) async {
  final watch = Stopwatch()..start();
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 3),
    );
    socket.destroy();
    return watch.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

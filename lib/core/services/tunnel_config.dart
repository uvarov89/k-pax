import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

const kClashPort = 9090;

/// Proven TUN (~9db533c / pre-1.0.51): IPv4-only. Dual-stack ULA + DoH +
/// Android `system` stack blackholed Win/Android while Hiddify with the same
/// sub worked (XP-10054 / mass K-Pax outage).
const _tunIpv4 = '172.19.0.1/30';

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

String buildTunnelConfig(
  TunnelNode node,
  ProSettings settings, {
  AppSettings? appSettings,
  bool enableStats = false,
  String? clashSecret,
}) {
  // Match proven path: only Ipv6Mode.enabled prefers IPv4 AAAA answers;
  // TUN stays IPv4-only and IPv6 is always rejected so apps use IPv4 via proxy.
  final ipv4Only = settings.ipv6Mode != Ipv6Mode.enabled;
  final dnsStrategy = ipv4Only ? 'ipv4_only' : 'prefer_ipv4';
  // Proven path: UDP DNS via proxy. DoH-over-proxy (1.0.51) left TUN Connected
  // with zero traffic on Android/Windows (XP-10054 / mass K-Pax reports).
  final remoteDnsTag = settings.dnsAutomatic ? 'dns-remote' : 'dns-direct';
  final outbound = Map<String, Object?>.from(node.outbound);
  if (InternetAddress.tryParse(node.host) == null) {
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
          'tag': 'dns-direct',
          'address': 'local',
          'detour': 'direct',
        },
        {
          'tag': 'dns-remote',
          'address': 'udp://1.1.1.1',
          'detour': 'proxy',
          'strategy': dnsStrategy,
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
        'address': [_tunIpv4],
        'mtu': 1400,
        'auto_route': true,
        'strict_route': settings.killSwitch,
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
      'default_domain_resolver': {
        'server': remoteDnsTag,
        'strategy': dnsStrategy,
      },
      'rules': _routeRules(appSettings),
      'final': _finalOutbound(appSettings),
    },
  });
}

List<Map<String, Object?>> _routeRules(AppSettings? appSettings) {
  final rules = <Map<String, Object?>>[
    {'action': 'sniff'},
    {'protocol': 'dns', 'action': 'hijack-dns'},
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
    // Proven: always reject IPv6 so apps fall back to IPv4 through the proxy.
    {'ip_version': 6, 'action': 'reject'},
  ];
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

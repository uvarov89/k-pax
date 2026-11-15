import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

const kClashPort = 9090;

/// IPv4 + ULA IPv6. IPv4-only TUN leaves ::/0 on clearnet — Telegram/Instagram
/// Happy-Eyeballs hang on broken ISP IPv6 while Hiddify (dual-stack TUN) works
/// with the same subscription.
const _tunIpv4 = '172.19.0.1/30';
const _tunIpv6 = 'fdfe:dcba:9876::1/126';

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
  // disabled (default): capture IPv6 into TUN and reject → apps use IPv4 via proxy.
  // enabled / tunnelOnly: keep IPv6 on TUN without reject.
  final allowIpv6 = settings.ipv6Mode != Ipv6Mode.disabled;
  final dnsStrategy = allowIpv6 ? 'prefer_ipv4' : 'ipv4_only';
  // TCP DNS via proxy (not UDP/53, not DoH). Survives exits that filter UDP
  // DNS; avoids the DoH+system-stack blackhole from 1.0.51.
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
          // sing-box 1.12+ DNS server schema; legacy "address" now fails
          // at startup unless an unsafe deprecated-feature flag is set.
          'tag': 'dns-direct',
          'type': 'local',
          'detour': 'direct',
        },
        {
          'tag': 'dns-remote',
          'type': 'tcp',
          'server': '1.1.1.1',
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
        'address': [_tunIpv4, _tunIpv6],
        'mtu': 1400,
        'auto_route': true,
        'strict_route': settings.killSwitch,
        // mixed is reliable on Android Libbox; `system` + dual-stack blackholed
        // traffic in 1.0.51 while Hiddify with the same sub worked.
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
      'rules': _routeRules(appSettings, allowIpv6: allowIpv6),
      'final': _finalOutbound(appSettings),
    },
  });
}

List<Map<String, Object?>> _routeRules(
  AppSettings? appSettings, {
  required bool allowIpv6,
}) {
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
  ];
  if (!allowIpv6) {
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

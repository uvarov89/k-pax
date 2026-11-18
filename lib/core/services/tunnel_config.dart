import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

const kClashPort = 9090;

/// Restored from the last known-good client shape (~1.0.50).
/// Breakage started at 1.0.51 ("stronger full-tunnel": dual-stack TUN, DoH,
/// Android system stack, QUIC reject, then a long Hiddify-parity hotfix chain).
/// Keep only proven surgical deltas for current sing-box / Windows / updates.
const _tunIpv4 = '172.19.0.1/30';
const _tunMtu = 1400;

/// Brand + GitHub must stay reachable for in-app updates while VPN is up.
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

String buildTunnelConfig(
  TunnelNode node,
  ProSettings settings, {
  AppSettings? appSettings,
  bool enableStats = false,
  String? clashSecret,
}) {
  // Same rule as 1.0.50: only prefer_ipv4 when IPv6 mode is fully enabled.
  final ipv4Only = settings.ipv6Mode != Ipv6Mode.enabled;
  final dnsStrategy = ipv4Only ? 'ipv4_only' : 'prefer_ipv4';
  // Windows: killSwitch default true must NOT enable strict_route (no safe WFP).
  final strictRoute = _windowsPlatform() ? false : settings.killSwitch;
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
          // 1.0.50: address=local via direct. New schema for sing-box 1.13.
          'tag': 'dns-direct',
          'type': 'local',
          'detour': 'direct',
        },
        {
          // 1.0.50: udp://1.1.1.1 via proxy (not TCP 8.8.8.8).
          'tag': 'dns-remote',
          'type': 'udp',
          'server': '1.1.1.1',
          'server_port': 53,
          'detour': 'proxy',
        },
      ],
      'rules': [
        {
          'domain_suffix': _updateDirectDomainSuffixes(),
          'domain': _updateDirectDomains,
          'server': 'dns-direct',
        },
      ],
      'final': settings.dnsAutomatic ? 'dns-remote' : 'dns-direct',
      'strategy': dnsStrategy,
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        // 1.0.50: IPv4-only /30 + MTU 1400 + mixed — always, regardless of IPv6 UI.
        'address': [_tunIpv4],
        'mtu': _tunMtu,
        'auto_route': true,
        'strict_route': strictRoute,
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
      'rules': _routeRules(appSettings, proxyHost: node.host),
      'final': _finalOutbound(appSettings),
    },
  });
}

List<Map<String, Object?>> _routeRules(
  AppSettings? appSettings, {
  String? proxyHost,
}) {
  // 1.0.50 route core: sniff → hijack-dns → private direct → reject IPv6.
  final updateDomains = List<String>.from(_updateDirectDomains);
  final host = (proxyHost ?? '').trim();
  // Never route the proxy endpoint through itself (front domain / exit IP).
  if (host.isNotEmpty && InternetAddress.tryParse(host) == null) {
    updateDomains.add(host);
  }
  final rules = <Map<String, Object?>>[
    {'action': 'sniff'},
    {'protocol': 'dns', 'action': 'hijack-dns'},
    {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
    {
      'domain_suffix': _updateDirectDomainSuffixes(),
      'domain': updateDomains,
      'action': 'route',
      'outbound': 'direct',
    },
    if (host.isNotEmpty && InternetAddress.tryParse(host) != null)
      {
        'ip_cidr': ['$host/32'],
        'action': 'route',
        'outbound': 'direct',
      },
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

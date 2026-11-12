import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

const kClashPort = 9090;

/// TUN IPv4 + ULA IPv6. Without an IPv6 TUN address the OS leaves ::/0 on
/// clearnet — censored apps (Telegram, Instagram, YouTube, …) can hang while
/// the VPN UI still shows Connected.
const _tunIpv4 = '172.19.0.1/30';
const _tunIpv6 = 'fdfe:dcba:9876::1/126';

String buildTunnelConfig(
  TunnelNode node,
  ProSettings settings, {
  AppSettings? appSettings,
  bool enableStats = false,
  String? clashSecret,
}) {
  final allowIpv6 = settings.ipv6Mode != Ipv6Mode.disabled;
  final dnsStrategy = allowIpv6 ? 'prefer_ipv4' : 'ipv4_only';
  // Anti-censorship: always resolve foreign names through the tunnel so ISP
  // poison/NXDOMAIN cannot hide YouTube, Instagram, OpenAI, Spotify, etc.
  // dnsAutomatic picks DoH vs UDP — both still detour=proxy, never ISP DNS.
  final remoteDnsTag =
      settings.dnsAutomatic ? 'dns-remote' : 'dns-remote-udp';
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
        // DoH via proxy — survives UDP/53 filtering on many exits.
        {
          'tag': 'dns-remote',
          'address': 'https://1.1.1.1/dns-query',
          'detour': 'proxy',
          'strategy': dnsStrategy,
        },
        {
          'tag': 'dns-remote-udp',
          'address': 'udp://1.1.1.1',
          'detour': 'proxy',
          'strategy': dnsStrategy,
        },
      ],
      'rules': [
        {
          'domain_suffix': [AppBrand.current.host, AppBrand.current.subHost],
          'server': 'dns-direct',
        },
      ],
      'final': remoteDnsTag,
      'strategy': dnsStrategy,
      'independent_cache': true,
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'address': [_tunIpv4, _tunIpv6],
        'mtu': 1280,
        'auto_route': true,
        'strict_route': settings.killSwitch,
        'stack': (!kIsWeb && Platform.isAndroid) ? 'system' : 'mixed',
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
  ];
  // Reality/VLESS is TCP-first. QUIC (HTTP/3) often stalls through it while the
  // same site works on TCP — reject QUIC so browsers/apps fall back to HTTPS.
  rules.add({'protocol': 'quic', 'action': 'reject'});
  // Capture IPv6 into TUN then drop → apps use IPv4 through the proxy.
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
  // Full-tunnel: every foreign site/app goes through the selected exit.
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

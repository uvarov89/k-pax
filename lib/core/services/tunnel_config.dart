import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

const kClashPort = 9090;

String buildTunnelConfig(
  TunnelNode node,
  ProSettings settings, {
  AppSettings? appSettings,
  bool enableStats = false,
  String? clashSecret,
}) {
  final ipv4Only = settings.ipv6Mode != Ipv6Mode.enabled;
  final outbound = Map<String, Object?>.from(node.outbound);
  if (InternetAddress.tryParse(node.host) == null) {
    outbound['domain_resolver'] = {
      'server': 'dns-direct',
      'strategy': ipv4Only ? 'ipv4_only' : 'prefer_ipv4',
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
        },
      ],
      'rules': [
        {
          'domain_suffix': ['k-pax.space'],
          'server': 'dns-direct',
        },
      ],
      'final': settings.dnsAutomatic ? 'dns-remote' : 'dns-direct',
      'strategy': ipv4Only ? 'ipv4_only' : 'prefer_ipv4',
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30'],
        'mtu': 1400,
        'auto_route': true,
        'strict_route': settings.killSwitch,
        'stack': 'mixed',
        'sniff': true,
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
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    socket.destroy();
    return watch.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

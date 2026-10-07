import 'dart:convert';
import 'dart:io';

import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

String buildTunnelConfig(TunnelNode node, ProSettings settings) {
  final ipv4Only = settings.ipv6Mode == Ipv6Mode.disabled;
  return jsonEncode({
    'log': {'level': 'warn', 'timestamp': true},
    'dns': {
      'servers': [
        {
          'tag': 'dns-remote',
          'address': 'udp://1.1.1.1',
          'detour': 'proxy',
        },
      ],
      'final': 'dns-remote',
      'strategy': ipv4Only ? 'ipv4_only' : 'prefer_ipv4',
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30'],
        'auto_route': true,
        'strict_route': true,
        'stack': 'mixed',
        'sniff': true,
      },
    ],
    'outbounds': [
      node.outbound,
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': {
      'auto_detect_interface': true,
      'rules': [
        {'protocol': 'dns', 'action': 'hijack-dns'},
        {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
      ],
      'final': 'proxy',
    },
  });
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

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';

void main() {
  final sample = <String, (TunnelKind, Map<String, Object?>)>{
    'reality': (TunnelKind.reality, {
      'type': 'vless', 'server': '203.0.113.10', 'server_port': 443,
      'uuid': '11111111-1111-1111-1111-111111111111',
      'flow': 'xtls-rprx-vision',
      'tls': {'enabled': true, 'server_name': 'www.example.com',
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {'enabled': true,
          'public_key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          'short_id': 'aabbccdd'}},
    }),
    'grpc': (TunnelKind.grpc, {
      'type': 'vless', 'server': 'grpc.example.com', 'server_port': 443,
      'uuid': '11111111-1111-1111-1111-111111111111',
      'transport': {'type': 'grpc', 'service_name': 'test'},
      'tls': {'enabled': true, 'server_name': 'grpc.example.com'},
    }),
    'ws': (TunnelKind.message, {
      'type': 'vless', 'server': 'edge.example.com', 'server_port': 443,
      'uuid': '11111111-1111-1111-1111-111111111111',
      'transport': {'type': 'ws', 'path': '/w/demo'},
      'tls': {'enabled': true, 'server_name': 'edge.example.com'},
    }),
    'hysteria2': (TunnelKind.hy2, {
      'type': 'hysteria2', 'server': '203.0.113.20',
      'server_port': 443, 'password': 'fake-password',
      'tls': {'enabled': true, 'server_name': 'h2.example.com', 'alpn': ['h3']},
    }),
    'tuic': (TunnelKind.tuic, {
      'type': 'tuic', 'server': '203.0.113.30', 'server_port': 443,
      'uuid': '11111111-1111-1111-1111-111111111111',
      'password': 'fake-password', 'congestion_control': 'bbr',
      'tls': {'enabled': true, 'server_name': 'tuic.example.com', 'alpn': ['h3']},
    }),
    'trojan': (TunnelKind.tls, {
      'type': 'trojan', 'server': 'trojan.example.com', 'server_port': 443,
      'password': 'fake-password',
      'tls': {'enabled': true, 'server_name': 'trojan.example.com'},
    }),
    'ss': (TunnelKind.shadowsocks, {
      'type': 'shadowsocks', 'server': '203.0.113.40',
      'server_port': 8388, 'method': 'aes-128-gcm', 'password': 'fake-password',
    }),
  };
  for (final entry in sample.entries) {
    for (final mode in [Ipv6Mode.disabled, Ipv6Mode.enabled]) {
      test('native config ${entry.key} IPv6=${mode.name}', () {
        final node = TunnelNode(
          countryId: 'de', countryCode: 'DE', countryName: 'Germany',
          kind: entry.value.$1,
          host: (entry.value.$2['server'] as String),
          port: entry.value.$2['server_port'] as int,
          outbound: {'tag': 'proxy', ...entry.value.$2},
        );
        final config = buildTunnelConfig(node, ProSettings(ipv6Mode: mode));
        final decoded = jsonDecode(config) as Map<String, dynamic>;
        expect((decoded['route'] as Map)['final'], 'proxy');
        final output = Platform.environment['NATIVE_CONFIG_OUT'];
        if (output != null && output.isNotEmpty) {
          Directory(output).createSync(recursive: true);
          File('$output/qa_${entry.key}_${mode.name}.json')
              .writeAsStringSync(config);
        }
      });
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';

void main() {
  test('emit native-checkable K-Pax config for both IPv6 policies', () {
    const sample = TunnelNode(
      countryId: 'de',
      countryCode: 'DE',
      countryName: 'Germany',
      kind: TunnelKind.reality,
      host: '203.0.113.10',
      port: 443,
      outbound: {
        'type': 'vless',
        'tag': 'proxy',
        'server': '203.0.113.10',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        'tls': {'enabled': true, 'server_name': 'example.com'},
      },
    );
    final output = Platform.environment['NATIVE_CONFIG_OUT'];
    for (final mode in [Ipv6Mode.disabled, Ipv6Mode.enabled]) {
      final config = buildTunnelConfig(
        sample,
        ProSettings(ipv6Mode: mode),
      );
      final parsed = jsonDecode(config) as Map<String, dynamic>;
      expect(parsed['outbounds'], isNotEmpty);
      expect((parsed['route'] as Map)['final'], 'proxy');
      if (output != null && output.isNotEmpty) {
        Directory(output).createSync(recursive: true);
        File('$output/${mode.name}.json').writeAsStringSync(config);
      }
    }
  });
}

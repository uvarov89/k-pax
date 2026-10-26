import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/split_tunnel.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/tunnel_config.dart';

void main() {
  const node = TunnelNode(
    countryId: 'de',
    countryCode: 'DE',
    countryName: 'Германия',
    kind: TunnelKind.reality,
    host: '203.0.113.10',
    port: 443,
    outbound: {'type': 'vless', 'tag': 'proxy'},
  );

  Map<String, Object?> config({
    bool killSwitch = true,
    bool dnsAutomatic = true,
    AppSettings? appSettings,
    bool enableStats = false,
  }) {
    return jsonDecode(
      buildTunnelConfig(
        node,
        ProSettings(killSwitch: killSwitch, dnsAutomatic: dnsAutomatic),
        appSettings: appSettings,
        enableStats: enableStats,
      ),
    ) as Map<String, Object?>;
  }

  test('kill switch and dns follow the settings', () {
    final on = config();
    final tun = (on['inbounds'] as List).first as Map;
    final dns = on['dns'] as Map;
    expect(tun['strict_route'], isTrue);
    expect(dns['final'], 'dns-remote');

    final off = config(killSwitch: false, dnsAutomatic: false);
    final tunOff = (off['inbounds'] as List).first as Map;
    expect(tunOff['strict_route'], isFalse);
    expect((off['dns'] as Map)['final'], 'dns-direct');
  });

  test('stats endpoint is added only when requested', () {
    expect(config()['experimental'], isNull);
    final stats = config(enableStats: true)['experimental'] as Map;
    expect((stats['clash_api'] as Map)['external_controller'], '127.0.0.1:9090');
  });

  test('selected windows programs can bypass the tunnel', () {
    final built = config(
      appSettings: const AppSettings(
        splitTunnelMode: SplitTunnelMode.excludeSelected,
        splitTunnelPackages: ['chrome.exe', 'not a name'],
      ),
    );
    final rules = (built['route'] as Map)['rules'] as List;
    final split = rules.cast<Map>().where((rule) => rule['process_name'] != null).toList();
    expect(split, hasLength(1));
    expect(split.first['process_name'], ['chrome.exe']);
    expect(split.first['outbound'], 'direct');
    expect((built['route'] as Map)['final'], 'proxy');
  });
}

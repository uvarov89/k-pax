import 'dart:convert';
import 'dart:io';

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

  test('restores 1.0.50-style TUN DNS and sniff', () {
    final built = config();
    final inbound = (built['inbounds'] as List).first as Map;
    expect(inbound.containsKey('sniff'), isFalse);
    expect(inbound['address'], ['172.19.0.1/30']);
    expect(inbound['mtu'], 1400);
    expect(inbound['stack'], 'mixed');
    // Windows never enables strict_route (no safe WFP kill switch yet).
    expect(inbound['strict_route'], Platform.isWindows ? isFalse : isTrue);

    final rules = (built['route'] as Map)['rules'] as List;
    expect(rules.first, {'action': 'sniff'});
    expect((built['route'] as Map).containsKey('default_domain_resolver'), isFalse);
    expect((built['route'] as Map).containsKey('override_android_vpn'), isFalse);

    final dns = built['dns'] as Map;
    expect(dns['final'], 'dns-remote');
    expect(dns['strategy'], 'ipv4_only');
    expect(
      (dns['servers'] as List).cast<Map>().any(
        (s) =>
            s['tag'] == 'dns-direct' &&
            s['type'] == 'local' &&
            s['detour'] == 'direct',
      ),
      isTrue,
    );
    expect(
      (dns['servers'] as List).cast<Map>().any(
        (s) =>
            s['tag'] == 'dns-remote' &&
            s['type'] == 'udp' &&
            s['server'] == '1.1.1.1' &&
            s['detour'] == 'proxy',
      ),
      isTrue,
    );
    expect(
      rules.cast<Map>().any(
        (r) => r['ip_version'] == 6 && r['action'] == 'reject',
      ),
      isTrue,
    );
    expect(
      rules.cast<Map>().any((r) => r['protocol'] == 'quic'),
      isFalse,
    );

    final off = config(killSwitch: false, dnsAutomatic: false);
    expect(((off['inbounds'] as List).first as Map)['strict_route'], isFalse);
    expect((off['dns'] as Map)['final'], 'dns-direct');
  });

  test('update and brand hosts bypass the tunnel for recovery downloads', () {
    final built = config();
    final routeRules = (built['route'] as Map)['rules'] as List;
    final direct = routeRules.cast<Map>().firstWhere(
      (r) =>
          r['outbound'] == 'direct' &&
          (r['domain_suffix'] as List?)?.contains('github.com') == true,
    );
    expect(direct['domain_suffix'], contains('github.com'));
    expect(direct['domain'], contains('release-assets.githubusercontent.com'));
  });

  test('IPv6 mode only changes DNS strategy; TUN stays IPv4-only', () {
    final enabled = jsonDecode(
      buildTunnelConfig(
        node,
        const ProSettings(ipv6Mode: Ipv6Mode.enabled),
      ),
    ) as Map<String, Object?>;
    expect((enabled['dns'] as Map)['strategy'], 'prefer_ipv4');
    expect(
      ((enabled['inbounds'] as List).first as Map)['address'],
      ['172.19.0.1/30'],
    );
    // 1.0.50 always rejected IPv6 in route rules.
    expect(
      ((enabled['route'] as Map)['rules'] as List).cast<Map>().any(
        (r) => r['ip_version'] == 6 && r['action'] == 'reject',
      ),
      isTrue,
    );
  });

  test('stats endpoint is added only when requested', () {
    expect(config()['experimental'], isNull);
    expect(
      jsonDecode(
        buildTunnelConfig(
          node,
          const ProSettings(),
          enableStats: true,
        ),
      )['experimental'],
      isNull,
    );
    final stats = jsonDecode(
      buildTunnelConfig(
        node,
        const ProSettings(),
        enableStats: true,
        clashSecret: 'session-secret',
      ),
    )['experimental'] as Map;
    expect((stats['clash_api'] as Map)['external_controller'], '127.0.0.1:9090');
    expect((stats['clash_api'] as Map)['secret'], 'session-secret');
  });

  test('selected windows programs can bypass the tunnel', () {
    final built = config(
      appSettings: const AppSettings(
        splitTunnelMode: SplitTunnelMode.excludeSelected,
        splitTunnelPackages: ['chrome.exe', 'not a name'],
      ),
    );
    final rules = (built['route'] as Map)['rules'] as List;
    final split =
        rules.cast<Map>().where((rule) => rule['process_name'] != null).toList();
    expect(split, hasLength(1));
    expect(split.first['process_name'], ['chrome.exe']);
    expect(split.first['outbound'], 'direct');
    expect((built['route'] as Map)['final'], 'proxy');
  }, skip: !Platform.isWindows);
}

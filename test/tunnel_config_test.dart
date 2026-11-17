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

  test('sniffing uses route actions supported by Libbox 1.13', () {
    final built = config();
    final inbound = (built['inbounds'] as List).first as Map;
    expect(inbound.containsKey('sniff'), isFalse);
    final rules = (built['route'] as Map)['rules'] as List;
    expect(rules.first, {'action': 'sniff', 'timeout': '300ms'});
  });

  test('kill switch and dns follow the settings', () {
    final on = config();
    final tun = (on['inbounds'] as List).first as Map;
    final dns = on['dns'] as Map;
    // Windows never enables strict_route (no safe WFP kill switch yet).
    expect(tun['strict_route'], Platform.isWindows ? isFalse : isTrue);
    expect(dns['final'], 'dns-remote');
    expect(tun['address'], ['172.19.0.1/28']);
    expect(tun['mtu'], 9000);
    expect(tun['stack'], 'mixed');
    expect(tun['endpoint_independent_nat'], isTrue);
    expect(dns['strategy'], 'ipv4_only');
    expect(
      (dns['servers'] as List).cast<Map>().any(
        (s) =>
            s['tag'] == 'dns-local' &&
            s['type'] == 'local' &&
            s['detour'] == 'direct',
      ),
      isTrue,
    );
    expect(
      (dns['servers'] as List).cast<Map>().any(
        (s) =>
            s['tag'] == 'dns-direct' &&
            s['type'] == 'udp' &&
            s['server'] == '1.1.1.1' &&
            s['server_port'] == 53 &&
            s['detour'] == 'direct',
      ),
      isTrue,
    );
    expect(
      (dns['servers'] as List).cast<Map>().any(
        (s) =>
            s['tag'] == 'dns-remote' &&
            s['type'] == 'tcp' &&
            s['server'] == '8.8.8.8' &&
            s['server_port'] == 53 &&
            s['detour'] == 'proxy',
      ),
      isTrue,
    );
    final route = on['route'] as Map;
    if (Platform.isAndroid) {
      expect(route['override_android_vpn'], isTrue);
    } else {
      expect(route.containsKey('override_android_vpn'), isFalse);
    }
    final rules = (route['rules'] as List).cast<Map>();
    expect(
      rules.any((r) => r['port'] == 53 && r['action'] == 'hijack-dns'),
      isTrue,
    );

    final off = config(killSwitch: false, dnsAutomatic: false);
    final tunOff = (off['inbounds'] as List).first as Map;
    expect(tunOff['strict_route'], isFalse);
    expect((off['dns'] as Map)['final'], 'dns-direct');
  });

  test('RU ISP portals bypass the tunnel by default', () {
    final built = config();
    final dnsRules = (built['dns'] as Map)['rules'] as List;
    final dnsDirect = dnsRules.cast<Map>().firstWhere(
      (r) => r['server'] == 'dns-direct',
    );
    expect(
      (dnsDirect['domain_suffix'] as List).cast<String>(),
      contains('beeline.ru'),
    );
    final routeRules = (built['route'] as Map)['rules'] as List;
    final isp = routeRules.cast<Map>().firstWhere(
      (r) =>
          r['outbound'] == 'direct' &&
          (r['domain_suffix'] as List?)?.contains('beeline.ru') == true,
    );
    expect(isp['domain_suffix'], contains('mts.ru'));
    expect(isp['domain'], contains('connectivitycheck.gstatic.com'));
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
    final dnsDirect = ((built['dns'] as Map)['rules'] as List).cast<Map>()
        .firstWhere((r) => r['server'] == 'dns-direct');
    expect(
      (dnsDirect['domain_suffix'] as List).cast<String>(),
      contains('github.com'),
    );
  });

  test('default IPv4-only TUN rejects IPv6; opt-in dual-stack; QUIC rejected', () {
    final disabled = config();
    final disabledRules = (disabled['route'] as Map)['rules'] as List;
    expect((disabled['route'] as Map)['final'], 'proxy');
    expect(
      disabledRules.cast<Map>().any(
        (r) => r['protocol'] == 'quic' && r['action'] == 'reject',
      ),
      isTrue,
    );
    expect(
      disabledRules.cast<Map>().any(
        (r) => r['ip_version'] == 6 && r['action'] == 'reject',
      ),
      isTrue,
    );
    expect(
      ((disabled['inbounds'] as List).first as Map)['address'],
      ['172.19.0.1/28'],
    );

    final tunnelOnly = jsonDecode(
      buildTunnelConfig(
        node,
        const ProSettings(ipv6Mode: Ipv6Mode.tunnelOnly),
      ),
    ) as Map<String, Object?>;
    expect(
      ((tunnelOnly['inbounds'] as List).first as Map)['address'],
      ['172.19.0.1/28', 'fdfe:dcba:9876::1/126'],
    );
    expect(
      ((tunnelOnly['route'] as Map)['rules'] as List).cast<Map>().any(
        (r) => r['ip_version'] == 6 && r['action'] == 'reject',
      ),
      isTrue,
    );

    final enabled = jsonDecode(
      buildTunnelConfig(
        node,
        const ProSettings(ipv6Mode: Ipv6Mode.enabled),
      ),
    ) as Map<String, Object?>;
    final enabledRules = (enabled['route'] as Map)['rules'] as List;
    expect(
      enabledRules.cast<Map>().any((r) => r['ip_version'] == 6),
      isFalse,
    );
    expect((enabled['dns'] as Map)['strategy'], 'prefer_ipv4');
    expect(
      ((enabled['inbounds'] as List).first as Map)['address'],
      ['172.19.0.1/28', 'fdfe:dcba:9876::1/126'],
    );
    expect(((enabled['inbounds'] as List).first as Map)['stack'], 'mixed');
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
    final split = rules.cast<Map>().where((rule) => rule['process_name'] != null).toList();
    expect(split, hasLength(1));
    expect(split.first['process_name'], ['chrome.exe']);
    expect(split.first['outbound'], 'direct');
    expect((built['route'] as Map)['final'], 'proxy');
  }, skip: !Platform.isWindows);
}

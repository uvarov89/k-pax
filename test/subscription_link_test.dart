import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/subscription_link.dart';

void main() {
  test('parses reality, spare grpc and ignores comments', () {
    const raw = '''
#providerid example
vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=publickey&sid=abcd&type=tcp#Германия
vless://11111111-1111-1111-1111-111111111111@de.example:8443?encryption=none&security=tls&sni=de.example&fp=chrome&alpn=h2&type=grpc&serviceName=kpax&mode=gun#Германия запасной
vless://11111111-1111-1111-1111-111111111111@203.0.113.20:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=publickey&sid=abcd&type=tcp#Финляндия
hy2://secret-password@203.0.113.10:443?insecure=1&sni=pulse-de#Германия Hy2
''';
    final encoded = base64Encode(utf8.encode(raw));
    final profile = parseSubscription(
      encoded,
      userinfo: 'upload=0; download=0; total=0; expire=1790000000',
    );

    expect(profile.nodes.map((node) => node.kind).toList(), [
      TunnelKind.reality,
      TunnelKind.grpc,
      TunnelKind.reality,
      TunnelKind.hy2,
    ]);
    expect(profile.nodes.first.countryId, 'de');
    expect(profile.nodes.first.countryName, 'Германия');
    expect(profile.nodes[1].countryName, 'Германия');
    expect(profile.nodes[1].outbound['flow'], isNull);
    expect(profile.nodes[2].countryId, 'fi');
    expect(profile.expiresAt, isNotNull);
    expect(
      kPaxSubscriptionUri('https://sub.k-pax.space/s/abcdefghijklmnopqrstuvwxyz')?.host,
      'sub.k-pax.space',
    );
    expect(kPaxSubscriptionUri('https://example.com/s/abcdefghijklmnopqrstuvwxyz'), isNull);
    expect(subscriptionAddress('https://example.com/sub')?.host, 'example.com');
    expect(looksLikeShare('vless://id@1.2.3.4:443#node'), isTrue);
    final trojan = parseSubscription(
      'trojan://secret@203.0.113.8:443?security=tls&sni=example.com#Amsterdam',
    );
    expect(trojan.nodes.single.outbound['type'], 'trojan');
    expect(trojan.nodes.single.host, '203.0.113.8');
  });

  test('keeps message lines and tuic out of the reality kind', () {
    const raw = '''
v2rayn://policygroup/abc
vless://11111111-1111-1111-1111-111111111111@k-pax.space:443?encryption=none&security=tls&sni=k-pax.space&fp=chrome&type=ws&host=k-pax.space&path=%2Fw%2Fde%2Fsecret#Германия сообщения
tuic://11111111-1111-1111-1111-111111111111:pass@de.example:2087?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=de.example&zero_rtt_handshake=1#Германия TUIC
''';
    final profile = parseSubscription(base64Encode(utf8.encode(raw)));
    expect(profile.nodes.map((node) => node.kind).toList(), [
      TunnelKind.message,
      TunnelKind.tuic,
    ]);
    expect(profile.nodes.first.countryName, 'Германия');
    expect(profile.nodes.first.outbound['transport'], {
      'type': 'ws',
      'path': '/w/de/secret',
      'headers': {'Host': 'k-pax.space'},
    });
    expect(profile.nodes[1].countryName, 'Германия');
    expect(profile.nodes[1].port, 2087);
    expect(profile.nodes[1].outbound['type'], 'tuic');
    expect(profile.nodes[1].outbound['password'], 'pass');
  });

  test('other providers: flags, names, codes and one bad line', () {
    final ssLegacy = base64Encode(utf8.encode('2022-blake3-aes-128-gcm:key@1.2.3.4:8388'));
    final vmess = base64Encode(utf8.encode(jsonEncode({
      'v': '2',
      'ps': 'Germany vmess',
      'add': '10.0.0.1',
      'port': '443',
      'id': '11111111-1111-1111-1111-111111111111',
      'net': 'grpc',
      'path': 'svc',
      'tls': 'tls',
      'sni': 'vm.example.net',
    })));
    final raw = '''
vless://11111111-1111-1111-1111-111111111111@nl.example.net:8443?security=tls&sni=nl.example.net&type=ws&path=%2Fws%3Fed%3D2048&host=cdn.example.net#%F0%9F%87%B3%F0%9F%87%B1%20Amsterdam%2001
vless://11111111-1111-1111-1111-111111111111@xh.example.net:443?security=tls&type=xhttp&path=%2Fx#Germany XHTTP
vless://broken-line-without-host
trojan://secret@us.example.net:443?security=tls&type=grpc&serviceName=tr#US-02 | Trojan
ss://$ssLegacy#Japan Tokyo
ss://2022-blake3-aes-128-gcm:a2V5@5.6.7.8:8443?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dexample.com#Белоруссия Минск
hysteria2://pass@9.9.9.9:443?obfs=salamander&obfs-password=x&sni=hy.example.net&pinSHA256=abcd#🇫🇮 Helsinki Hy2
vmess://$vmess
vless://11111111-1111-1111-1111-111111111111@j.example.net:443?security=tls&type=tcp&headerType=http#Jerusalem
''';
    final profile = parseSubscription(base64Encode(utf8.encode(raw)));
    final byTitle = {for (final node in profile.nodes) node.host: node};
    expect(profile.nodes.length, 6);
    final nl = byTitle['nl.example.net']!;
    expect(nl.countryCode, 'NL');
    expect(nl.countryName, 'Нидерланды');
    expect(nl.kind, TunnelKind.message);
    expect(nl.port, 8443);
    expect(nl.outbound['transport'], {
      'type': 'ws',
      'max_early_data': 2048,
      'early_data_header_name': 'Sec-WebSocket-Protocol',
      'path': '/ws',
      'headers': {'Host': 'cdn.example.net'},
    });
    final us = byTitle['us.example.net']!;
    expect(us.countryCode, 'US');
    expect(us.kind, TunnelKind.grpc);
    expect(us.outbound['transport'], {'type': 'grpc', 'service_name': 'tr'});
    expect(byTitle['1.2.3.4']!.countryCode, 'JP');
    expect(byTitle['1.2.3.4']!.outbound['method'], '2022-blake3-aes-128-gcm');
    final by = byTitle['5.6.7.8']!;
    expect(by.countryCode, 'BY');
    expect(by.outbound['plugin'], 'obfs-local');
    expect(by.outbound['plugin_opts'], 'obfs=http;obfs-host=example.com');
    final fi = byTitle['9.9.9.9']!;
    expect(fi.countryCode, 'FI');
    expect(fi.kind, TunnelKind.hy2);
    expect(fi.outbound['obfs'], {'type': 'salamander', 'password': 'x'});
    expect((fi.outbound['tls'] as Map)['insecure'], isTrue);
    final vm = byTitle['10.0.0.1']!;
    expect(vm.countryCode, 'DE');
    expect(vm.outbound['transport'], {'type': 'grpc', 'service_name': 'svc'});
    expect(byTitle.containsKey('xh.example.net'), isFalse);
    expect(byTitle.containsKey('j.example.net'), isFalse);
  });

  test('reads Clash proxies and skips the ones it cannot run', () {
    const yaml = '''
mixed-port: 7890
proxies:
  - name: "🇳🇱 Amsterdam"
    type: vless
    server: nl.example.net
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    network: tcp
    tls: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: pubkey
      short-id: ab12
  - name: Germany WS
    type: vmess
    server: de.example.net
    port: 8443
    uuid: 22222222-2222-2222-2222-222222222222
    alterId: 0
    cipher: auto
    tls: true
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: cdn.example.net
  - name: Finland Hy2
    type: hysteria2
    server: 9.9.9.9
    port: 443
    password: pass
    sni: hy.example.net
    skip-cert-verify: true
  - name: SS Japan
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: chacha20-ietf-poly1305
    password: pw
  - name: Wireguard
    type: wireguard
    server: 5.5.5.5
    port: 51820
proxy-groups:
  - name: auto
    type: url-test
    proxies: [a]
''';
    final profile = parseSubscription(yaml);
    expect(profile.nodes.map((node) => node.countryCode).toList(), ['NL', 'DE', 'FI', 'JP']);
    final nl = profile.nodes[0];
    expect(nl.kind, TunnelKind.reality);
    expect(nl.outbound['flow'], 'xtls-rprx-vision');
    expect((nl.outbound['tls'] as Map)['reality'], {
      'enabled': true,
      'public_key': 'pubkey',
      'short_id': 'ab12',
    });
    expect((nl.outbound['tls'] as Map)['server_name'], 'www.microsoft.com');
    final de = profile.nodes[1];
    expect(de.kind, TunnelKind.message);
    expect(de.outbound['transport'], {
      'type': 'ws',
      'path': '/ws',
      'headers': {'Host': 'cdn.example.net'},
    });
    expect((profile.nodes[2].outbound['tls'] as Map)['insecure'], isTrue);
    expect(profile.nodes[3].outbound['method'], 'chacha20-ietf-poly1305');
  });

  test('reads sing-box and Xray JSON subscriptions', () {
    final singbox = jsonEncode({
      'outbounds': [
        {'type': 'selector', 'tag': 'select', 'outbounds': ['de']},
        {
          'type': 'vless',
          'tag': '🇩🇪 Frankfurt',
          'server': 'de.example.net',
          'server_port': 443,
          'uuid': '11111111-1111-1111-1111-111111111111',
          'detour': 'other',
          'tls': {'enabled': true, 'server_name': 'de.example.net'},
          'transport': {'type': 'grpc', 'service_name': 'svc'},
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
    });
    final fromSingbox = parseSubscription(singbox);
    expect(fromSingbox.nodes.single.countryCode, 'DE');
    expect(fromSingbox.nodes.single.kind, TunnelKind.grpc);
    expect(fromSingbox.nodes.single.outbound['tag'], 'proxy');
    expect(fromSingbox.nodes.single.outbound.containsKey('detour'), isFalse);

    Map<String, Object?> xray(String remarks, String address, String network) => {
          'remarks': remarks,
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': address,
                    'port': 443,
                    'users': [
                      {'id': '11111111-1111-1111-1111-111111111111', 'flow': 'xtls-rprx-vision'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': network,
                'security': 'reality',
                'realitySettings': {
                  'serverName': 'www.microsoft.com',
                  'fingerprint': 'chrome',
                  'publicKey': 'pk',
                  'shortId': 'cd',
                },
              },
            },
            {'tag': 'direct', 'protocol': 'freedom'},
          ],
        };
    final fromXray = parseSubscription(jsonEncode([
      xray('Финляндия', '203.0.113.20', 'tcp'),
      xray('Финляндия', '203.0.113.20', 'tcp'),
      xray('Germany XHTTP', '203.0.113.10', 'xhttp'),
    ]));
    final fi = fromXray.nodes.single;
    expect(fi.countryCode, 'FI');
    expect(fi.outbound['flow'], 'xtls-rprx-vision');
    expect((fi.outbound['tls'] as Map)['reality'], {
      'enabled': true,
      'public_key': 'pk',
      'short_id': 'cd',
    });
  });

  test('a config file without usable servers says so', () {
    expect(
      () => parseSubscription('proxies:\n  - name: a\n    type: wireguard\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('reads the provider name from profile-title', () {
    expect(profileTitle('base64:${base64Encode(utf8.encode('X-Plm'))}'), 'X-Plm');
    expect(profileTitle('My VPN'), 'My VPN');
    expect(profileTitle(''), isNull);
    expect(providerPage('https://example.com/help')?.host, 'example.com');
    expect(providerPage('javascript:alert(1)'), isNull);
  });

  test('names Bulgaria from the subscription title', () {
    final profile = parseSubscription(
      'vless://11111111-1111-1111-1111-111111111111@79.124.7.111:443?encryption=none&type=tcp#Болгария',
    );
    expect(profile.nodes.single.countryId, 'bg');
    expect(profile.nodes.single.countryCode, 'BG');
    expect(profile.nodes.single.countryName, 'Болгария');
  });
}

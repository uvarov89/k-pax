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

  test('names Bulgaria from the subscription title', () {
    final profile = parseSubscription(
      'vless://11111111-1111-1111-1111-111111111111@79.124.7.111:443?encryption=none&type=tcp#Болгария',
    );
    expect(profile.nodes.single.countryId, 'bg');
    expect(profile.nodes.single.countryCode, 'BG');
    expect(profile.nodes.single.countryName, 'Болгария');
  });
}

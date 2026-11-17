import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/models/server_location.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

/// Two real profiles may share host:port but differ in UUID, SNI or transport.
/// Failing to try the second profile makes the proprietary app fail even if
/// the provider's second profile works in Happ/Hiddify.
class _FailFirstVpn implements VpnService {
  _FailFirstVpn({this.failAlways = false});

  final bool failAlways;
  final List<TunnelNode> attempts = [];

  @override
  Stream<String> get statusStream => const Stream.empty();

  @override
  Stream<TunnelSpeed> get trafficStream => const Stream.empty();

  @override
  Future<void> connect({
    required ServerLocation location,
    required ProSettings settings,
    required AppSettings appSettings,
    required TunnelNode node,
  }) async {
    attempts.add(node);
    if (failAlways || attempts.length == 1) {
      throw StateError('simulated handshake failure');
    }
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<Map<String, int>> probeNodes() async => {};
}

void main() {
  test('failover retries distinct profile on same host and port', () async {
    const first = TunnelNode(
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
        'tls': {'server_name': 'front1.example'},
      },
    );
    const second = TunnelNode(
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
        'uuid': '22222222-2222-2222-2222-222222222222',
        'tls': {'server_name': 'front2.example'},
      },
    );

    final service = _FailFirstVpn();
    final controller = VpnController(service: service)
      ..subscriptionUrl = 'https://sub.example/s/fake-test'
      ..linkState = SubscriptionLinkState.ready
      ..profile = const SubscriptionProfile(nodes: [first, second])
      ..account = UserAccount.freshTrial()
      ..locationMode = LocationMode.country
      ..selectedLocation = const ServerLocation(
        id: 'de',
        countryCode: 'DE',
        nameRu: 'Германия',
      )
      ..proSettings = const ProSettings(protocolFallback: true);
    addTearDown(controller.dispose);

    final ok = await controller.connect();
    expect(ok, isTrue);
    expect(controller.isConnected, isTrue);
    expect(service.attempts, hasLength(2));
    expect(service.attempts[0].outbound, isNot(service.attempts[1].outbound));
  });
  test('failover respects attempt budget and cannot spin on untried spares', () async {
    final nodes = List<TunnelNode>.generate(
      12,
      (i) => TunnelNode(
        countryId: 'de',
        countryCode: 'DE',
        countryName: 'Germany',
        kind: TunnelKind.reality,
        host: '203.0.113.${i + 1}',
        port: 443,
        outbound: {
          'type': 'vless',
          'tag': 'proxy',
          'server': '203.0.113.${i + 1}',
          'server_port': 443,
          'uuid': '11111111-1111-1111-1111-111111111111',
        },
      ),
    );
    final service = _FailFirstVpn(failAlways: true);
    final controller = VpnController(service: service)
      ..subscriptionUrl = 'https://sub.example/s/fake-test'
      ..linkState = SubscriptionLinkState.ready
      ..profile = SubscriptionProfile(nodes: nodes)
      ..account = UserAccount.freshTrial()
      ..locationMode = LocationMode.country
      ..selectedLocation = const ServerLocation(
        id: 'de',
        countryCode: 'DE',
        nameRu: 'Германия',
      )
      ..proSettings = const ProSettings(protocolFallback: true);
    addTearDown(controller.dispose);

    final ok = await controller.connect().timeout(const Duration(seconds: 5));
    expect(ok, isFalse);
    expect(controller.isConnected, isFalse);
    expect(service.attempts, hasLength(8));
  });

}
